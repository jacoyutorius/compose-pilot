# frozen_string_literal: true

require "json"
require "open3"
require "sinatra/base"

require_relative "lib/compose_runner"
require_relative "lib/command_body"
require_relative "lib/operation_registry"
require_relative "lib/project_locator"
require_relative "lib/runtime_identity"

module ComposePilot
  class App < Sinatra::Base
    set :bind, "0.0.0.0"
    set :port, ENV.fetch("PORT", "8080")
    set :server, :puma
    set :public_folder, File.expand_path("web", __dir__)
    set :static, true
    set :static_cache_control, [:no_store]

    configure do
      container_root = ENV.fetch("PROJECT_ROOT", "/workspace")
      host_root = ENV.fetch("HOST_PROJECT_ROOT")
      generated_dir = ENV.fetch("GENERATED_DIR", "/data/generated")
      allow_self_operation = ENV.fetch("ALLOW_SELF_OPERATION", "false") == "true"

      compose_file = ProjectLocator.new(container_root: container_root).compose_file
      identity = RuntimeIdentityResolver.new(
        container_id: ENV.fetch("HOSTNAME", ""),
        project_name: ENV["COMPOSE_PROJECT_NAME"],
        service_name: ENV["COMPOSE_PILOT_SERVICE"]
      ).resolve
      runner = ComposeRunner.new(
        container_root: container_root,
        host_root: host_root,
        generated_dir: generated_dir,
        compose_file: compose_file,
        project_name: identity.project_name,
        self_service: identity.service_name,
        allow_self_operation: allow_self_operation
      )

      set :runner, runner
      set :operations, OperationRegistry.new
    end

    before do
      headers(
        "X-Content-Type-Options" => "nosniff",
        "X-Frame-Options" => "DENY",
        "Cache-Control" => "no-store",
        "Content-Security-Policy" => "default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self'"
      )
    end

    helpers do
      def json_response(value, status: 200)
        content_type :json
        halt status, JSON.generate(value)
      end

      def request_json
        JSON.parse(request.body.read)
      rescue JSON::ParserError
        json_response({ error: "リクエストが正しくありません" }, status: 400)
      end

      def command_response(command, operation_key: nil)
        if operation_key && !settings.operations.acquire(operation_key)
          return json_response({ error: "このプロジェクトでは別の操作を実行中です" }, status: 409)
        end

        release = operation_key ? -> { settings.operations.release(operation_key) } : nil
        body = CommandBody.new(command, on_close: release)
        [
          200,
          {
            "content-type" => "text/plain; charset=utf-8",
            "cache-control" => "no-store",
            "x-accel-buffering" => "no"
          },
          body
        ]
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

    get "/api/project" do
      json_response(settings.runner.project)
    rescue ComposeError => e
      json_response({ error: e.message }, status: 400)
    end

    get "/api/status" do
      output, success = settings.runner.status
      json_response({ output: output, ok: success })
    rescue ComposeError => e
      json_response({ error: e.message }, status: 400)
    end

    post "/api/actions" do
      body = request_json
      commands = settings.runner.action_commands(
        action: body["action"].to_s,
        services: Array(body["services"]).map(&:to_s),
        no_cache: body["noCache"] == true,
        build_args: Array(body["buildArgs"])
      )
      command_response(commands, operation_key: "project")
    rescue ComposeError => e
      json_response({ error: e.message }, status: 400)
    end

    get "/api/logs" do
      command_response(settings.runner.logs_command(service: params["service"]))
    rescue ComposeError => e
      json_response({ error: e.message }, status: 400)
    end

    error do
      json_response({ error: "予期しないエラーが発生しました" }, status: 500)
    end
  end
end
