# frozen_string_literal: true

require "digest"
require "find"
require "pathname"

module ComposePilot
  Project = Data.define(:id, :name, :relative, :file) do
    def to_h
      { id: id, name: name, relative: relative, file: file }
    end
  end

  class ProjectRegistry
    COMPOSE_FILES = %w[compose.yaml compose.yml docker-compose.yaml docker-compose.yml].freeze
    IGNORED_DIRECTORIES = %w[node_modules vendor].freeze

    def initialize(container_root:)
      @container_root = File.expand_path(container_root)
    end

    def all
      return [] unless Dir.exist?(@container_root)

      projects = []
      Find.find(@container_root) do |path|
        if File.directory?(path)
          name = File.basename(path)
          Find.prune if path != @container_root && (name.start_with?(".") || IGNORED_DIRECTORIES.include?(name))
          next
        end
        next unless COMPOSE_FILES.include?(File.basename(path))

        directory = File.dirname(path)
        relative = Pathname(directory).relative_path_from(Pathname(@container_root)).to_s
        relative = "." if relative.empty?
        file = File.basename(path)
        name = relative == "." ? "workspace" : File.basename(directory)
        id = Digest::SHA256.hexdigest("#{relative}\0#{file}")[0, 16]
        projects << Project.new(id:, name:, relative:, file:)
      end
      projects.sort_by(&:relative)
    end

    def find(id)
      all.find { |project| project.id == id }
    end
  end
end
