# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "pathname"
require "shellwords"
require "yaml"

module ComposePilot
  class ComposeError < StandardError; end

  class ComposeRunner
    ACTIONS = {
      "build" => ["build"],
      "up" => ["up", "-d"],
      "build-up" => ["up", "--build", "-d"],
      "stop" => ["stop"],
      "restart" => ["restart"],
      "remove" => ["rm", "--stop", "--force"]
    }.freeze

    def initialize(container_root:, host_root:, generated_dir:, compose_file:, project_name:, self_service:, allow_self_operation: false)
      raise ComposeError, "HOST_PROJECT_ROOTには絶対パスを指定してください" unless Pathname(host_root).absolute?

      @container_root = File.expand_path(container_root)
      @host_root = File.expand_path(host_root)
      @generated_dir = File.expand_path(generated_dir)
      @compose_file = compose_file
      @project_name = project_name
      @self_service = self_service
      @allow_self_operation = allow_self_operation
      FileUtils.mkdir_p(@generated_dir)
    end

    def project
      config = compose_config
      service_names = config.fetch("services", {}).keys
      validate_self_service!(service_names)
      {
        name: config.fetch("name", File.basename(@host_root)),
        file: @compose_file,
        services: service_names.map do |name|
          { name: name, self: name == @self_service, selectable: name != @self_service || @allow_self_operation }
        end,
        allowSelfOperation: @allow_self_operation
      }
    end

    def status
      stdout, stderr, process = Open3.capture3(*base_command, "ps", "--format", "json")
      [stdout.empty? ? stderr : stdout, process.success?]
    end

    def action_command(action:, services:, no_cache: false)
      operation = ACTIONS[action]&.dup
      raise ComposeError, "対応していない操作です" unless operation

      config = compose_config
      known_services = config.fetch("services", {}).keys
      validate_self_service!(known_services)
      unknown_services = services - known_services
      raise ComposeError, "存在しないサービスが指定されています: #{unknown_services.join(', ')}" unless unknown_services.empty?
      if services.include?(@self_service) && !@allow_self_operation
        raise ComposeError, "Compose Pilot自身は操作できません"
      end

      target_services = services.empty? ? known_services - [@self_service] : services
      raise ComposeError, "操作対象のサービスがありません" if target_services.empty?

      operation << "--no-cache" if action == "build" && no_cache
      operation.concat(target_services)
      [*base_command, *operation]
    end

    def logs_command(service: nil)
      config = compose_config
      known_services = config.fetch("services", {}).keys
      validate_self_service!(known_services)
      command = [*base_command, "logs", "--tail", "200", "--follow", "--no-color"]
      if service && !service.empty?
        raise ComposeError, "存在しないサービスです" unless known_services.include?(service)
        command << service
      else
        command.concat(known_services - [@self_service])
      end
      command
    end

    def path_within?(path, root = @container_root)
      expanded_path = File.expand_path(path)
      expanded_root = File.expand_path(root)
      expanded_path == expanded_root || expanded_path.start_with?(expanded_root + File::SEPARATOR)
    end

    private

    def original_command
      file = File.expand_path(@compose_file, @container_root)
      raise ComposeError, "プロジェクトルート外のComposeファイルです" unless path_within?(file)

      ["docker", "compose", "--project-name", @project_name, "--project-directory", @container_root, "-f", file]
    end

    def base_command
      command = original_command
      override = generate_override
      override ? [*command, "-f", override] : command
    end

    def generate_override
      config = compose_config
      services = {}
      config.fetch("services", {}).each do |service_name, service|
        mounts = Array(service["volumes"]).filter_map { |volume| translated_mount(volume) }
        services[service_name] = { "volumes" => mounts } unless mounts.empty?
      end
      return nil if services.empty?

      path = File.join(@generated_dir, "project.paths.yaml")
      File.write(path, { "services" => services }.to_yaml)
      path
    end

    def compose_config
      stdout, stderr, status = Open3.capture3(*original_command, "config", "--format", "json")
      raise ComposeError, compose_error(stderr, stdout) unless status.success?

      JSON.parse(stdout)
    rescue JSON::ParserError => e
      raise ComposeError, "Compose設定を読み取れませんでした: #{e.message}"
    end

    def validate_self_service!(services)
      return if services.include?(@self_service)

      raise ComposeError, "実行中のCompose PilotサービスがCompose設定に見つかりません: #{@self_service}"
    end

    def translated_mount(volume)
      return unless volume["type"] == "bind"
      return unless path_within?(volume["source"])

      relative = Pathname(File.expand_path(volume["source"])).relative_path_from(Pathname(@container_root)).to_s
      mount = {
        "type" => "bind",
        "source" => File.expand_path(relative, @host_root),
        "target" => volume.fetch("target")
      }
      mount["read_only"] = true if volume["read_only"]
      mount
    end

    def compose_error(stderr, stdout)
      message = [stderr, stdout].find { |value| !value.to_s.strip.empty? }
      "Compose設定の処理に失敗しました: #{message.to_s.strip}"
    end
  end
end
