# frozen_string_literal: true

require "json"
require "open3"
require_relative "compose_runner"

module ComposePilot
  RuntimeIdentity = Data.define(:project_name, :service_name)

  class RuntimeIdentityResolver
    PROJECT_LABEL = "com.docker.compose.project"
    SERVICE_LABEL = "com.docker.compose.service"

    def initialize(container_id:, project_name: nil, service_name: nil)
      @container_id = container_id
      @project_name = project_name
      @service_name = service_name
    end

    def resolve
      return RuntimeIdentity.new(project_name: @project_name, service_name: @service_name) if @project_name && @service_name

      stdout, stderr, status = Open3.capture3("docker", "inspect", @container_id)
      raise ComposeError, "Compose Pilotコンテナを識別できません: #{stderr.strip}" unless status.success?

      labels = JSON.parse(stdout).first.fetch("Config", {}).fetch("Labels", {})
      project_name = @project_name || labels[PROJECT_LABEL]
      service_name = @service_name || labels[SERVICE_LABEL]
      raise ComposeError, "Composeプロジェクト名を識別できません" if project_name.to_s.empty?
      raise ComposeError, "Compose Pilotのサービス名を識別できません" if service_name.to_s.empty?

      RuntimeIdentity.new(project_name:, service_name:)
    rescue JSON::ParserError, KeyError => e
      raise ComposeError, "Compose Pilotコンテナの情報を読み取れませんでした: #{e.message}"
    end
  end
end
