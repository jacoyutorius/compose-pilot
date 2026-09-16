# frozen_string_literal: true

require_relative "compose_runner"

module ComposePilot
  class ProjectLocator
    COMPOSE_FILES = %w[compose.yaml compose.yml docker-compose.yaml docker-compose.yml].freeze

    def initialize(container_root:)
      @container_root = File.expand_path(container_root)
    end

    def compose_file
      raise ComposeError, "プロジェクトディレクトリが見つかりません: #{@container_root}" unless Dir.exist?(@container_root)

      files = COMPOSE_FILES.select { |name| File.file?(File.join(@container_root, name)) }
      raise ComposeError, "Composeファイルが見つかりません" if files.empty?
      raise ComposeError, "Composeファイルが複数見つかりました: #{files.join(', ')}" if files.size > 1

      files.first
    end
  end
end
