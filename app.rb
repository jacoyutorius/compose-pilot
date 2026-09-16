# frozen_string_literal: true

require "json"
require "open3"
require "sinatra/base"

require_relative "lib/compose_runner"
require_relative "lib/project_registry"

module ComposePilot
  class App < Sinatra::Base
    set :bind, "0.0.0.0"
    set :port, ENV.fetch("PORT", "8080")
    set :server, :puma
    set :public_folder, File.expand_path("web", __dir__)
    set :static, true

    configure do
      container_root = ENV.fetch("PROJECTS_ROOT", "/workspace")
      host_root = ENV.fetch("HOST_PROJECTS_ROOT")
      generated_dir = ENV.fetch("GENERATED_DIR", "/data/generated")

      registry = ProjectRegistry.new(container_root: container_root)
      runner = ComposeRunner.new(
        container_root: container_root,
        host_root: host_root,
        generated_dir: generated_dir
      )

      set :registry, registry
      set :runner, runner
    end

    before do
      headers(
        "X-Content-Type-Options" => "nosniff",
        "X-Frame-Options" => "DENY",
        "Content-Security-Policy" => "default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self'"
      )
    end

    helpers do
      def json_response(value, status: 200)
        content_type :json
        halt status, JSON.generate(value)
      end

      def project!
        settings.registry.find(params.fetch("id")) || json_response({ error: "プロジェクトが見つかりません" }, status: 404)
      end

      def request_json
        JSON.parse(request.body.read)
      rescue JSON::ParserError
        json_response({ error: "リクエストが正しくありません" }, status: 400)
      end

      def stream_command(command)
        content_type "text/plain", charset: "utf-8"
        headers "Cache-Control" => "no-store"

        stream(:keep_open) do |output|
          Thread.new do
            begin
              output << "$ #{Shellwords.shelljoin(command)}\n\n"
              Open3.popen2e(*command) do |_stdin, combined, wait_thread|
                combined.each_line { |line| output << line }
                status = wait_thread.value
                output << (status.success? ? "\n完了しました。\n" : "\nコマンドの実行に失敗しました（終了コード: #{status.exitstatus}）。\n")
              end
            rescue StandardError => e
              output << "\nエラー: #{e.message}\n"
            ensure
              output.close
            end
          end
        end
      end
    end

    get "/" do
      send_file File.join(settings.public_folder, "index.html")
    end

    get "/api/health" do
      stdout, _stderr, status = Open3.capture3("docker", "version", "--format", "{{.Server.Version}}")
      json_response({ ok: status.success?, dockerVersion: stdout.strip })
    rescue Errno::ENOENT
      json_response({ ok: false, dockerVersion: "" })
    end

    get "/api/projects" do
      json_response(settings.registry.all.map(&:to_h))
    end

    get "/api/projects/:id/config" do
      project = project!
      json_response({ services: settings.runner.services(project) })
    rescue ComposeError => e
      json_response({ error: e.message }, status: 400)
    end

    get "/api/projects/:id/status" do
      project = project!
      output, success = settings.runner.status(project)
      json_response({ output: output, ok: success })
    rescue ComposeError => e
      json_response({ error: e.message }, status: 400)
    end

    post "/api/actions" do
      body = request_json
      project = settings.registry.find(body["projectId"].to_s)
      json_response({ error: "プロジェクトが見つかりません" }, status: 404) unless project

      command = settings.runner.action_command(
        project,
        action: body["action"].to_s,
        services: Array(body["services"]).map(&:to_s),
        no_cache: body["noCache"] == true
      )
      stream_command(command)
    rescue ComposeError => e
      json_response({ error: e.message }, status: 400)
    end

    get "/api/projects/:id/logs" do
      project = project!
      stream_command(settings.runner.logs_command(project, service: params["service"]))
    rescue ComposeError => e
      json_response({ error: e.message }, status: 400)
    end

    error do
      json_response({ error: "予期しないエラーが発生しました" }, status: 500)
    end
  end
end
