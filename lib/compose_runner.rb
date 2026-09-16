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
      "down" => ["down"]
    }.freeze

    def initialize(container_root:, host_root:, generated_dir:)
      @container_root = File.expand_path(container_root)
      @host_root = File.expand_path(host_root)
      @generated_dir = File.expand_path(generated_dir)
      FileUtils.mkdir_p(@generated_dir)
    end

    def services(project)
      stdout, stderr, status = Open3.capture3(*original_command(project), "config", "--services")
      raise ComposeError, compose_error(stderr, stdout) unless status.success?

      stdout.lines(chomp: true).reject(&:empty?)
    end

    def status(project)
      stdout, stderr, process = Open3.capture3(*base_command(project), "ps", "--format", "json")
      [stdout.empty? ? stderr : stdout, process.success?]
    end

    def action_command(project, action:, services:, no_cache: false)
      operation = ACTIONS[action]&.dup
      raise ComposeError, "対応していない操作です" unless operation

      known_services = self.services(project)
      unknown_services = services - known_services
      raise ComposeError, "存在しないサービスが指定されています: #{unknown_services.join(', ')}" unless unknown_services.empty?

      operation << "--no-cache" if action == "build" && no_cache
      operation.concat(services) unless action == "down"
      [*base_command(project), *operation]
    end

    def logs_command(project, service: nil)
      command = [*base_command(project), "logs", "--tail", "200", "--follow", "--no-color"]
      if service && !service.empty?
        raise ComposeError, "存在しないサービスです" unless services(project).include?(service)
        command << service
      end
      command
    end

    def path_within?(path, root = @container_root)
      expanded_path = File.expand_path(path)
      expanded_root = File.expand_path(root)
      expanded_path == expanded_root || expanded_path.start_with?(expanded_root + File::SEPARATOR)
    end

    private

    def project_paths(project)
      directory = File.expand_path(project.relative, @container_root)
      raise ComposeError, "プロジェクトルート外のパスです" unless path_within?(directory)

      [directory, File.join(directory, project.file)]
    end

    def original_command(project)
      directory, file = project_paths(project)
      ["docker", "compose", "--project-directory", directory, "-f", file]
    end

    def base_command(project)
      command = original_command(project)
      override = generate_override(project)
      override ? [*command, "-f", override] : command
    end

    def generate_override(project)
      stdout, stderr, status = Open3.capture3(*original_command(project), "config", "--format", "json")
      raise ComposeError, compose_error(stderr, stdout) unless status.success?

      config = JSON.parse(stdout)
      services = {}
      config.fetch("services", {}).each do |service_name, service|
        mounts = Array(service["volumes"]).filter_map { |volume| translated_mount(volume) }
        services[service_name] = { "volumes" => mounts } unless mounts.empty?
      end
      return nil if services.empty?

      path = File.join(@generated_dir, "#{project.id}.paths.yaml")
      File.write(path, { "services" => services }.to_yaml)
      path
    rescue JSON::ParserError => e
      raise ComposeError, "Compose設定を読み取れませんでした: #{e.message}"
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
