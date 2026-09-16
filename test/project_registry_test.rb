# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/project_registry"

class ProjectRegistryTest < Minitest::Test
  def test_compose_projects_are_found
    Dir.mktmpdir do |root|
      Dir.mkdir(File.join(root, "sample"))
      File.write(File.join(root, "sample", "compose.yaml"), "services: {}\n")

      projects = ComposePilot::ProjectRegistry.new(container_root: root).all

      assert_equal 1, projects.size
      assert_equal "sample", projects.first.name
      assert_equal "sample", projects.first.relative
    end
  end

  def test_ignored_directories_are_skipped
    Dir.mktmpdir do |root|
      Dir.mkdir(File.join(root, "node_modules"))
      File.write(File.join(root, "node_modules", "compose.yaml"), "services: {}\n")

      assert_empty ComposePilot::ProjectRegistry.new(container_root: root).all
    end
  end
end
