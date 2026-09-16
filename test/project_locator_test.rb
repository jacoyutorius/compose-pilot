# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/compose_runner"
require_relative "../lib/project_locator"

class ProjectLocatorTest < Minitest::Test
  def test_finds_compose_file_directly_under_project_root
    Dir.mktmpdir do |root|
      File.write(File.join(root, "compose.yaml"), "services: {}\n")

      assert_equal "compose.yaml", ComposePilot::ProjectLocator.new(container_root: root).compose_file
    end
  end

  def test_does_not_search_child_directories
    Dir.mktmpdir do |root|
      Dir.mkdir(File.join(root, "sample"))
      File.write(File.join(root, "sample", "compose.yaml"), "services: {}\n")

      error = assert_raises(ComposePilot::ComposeError) do
        ComposePilot::ProjectLocator.new(container_root: root).compose_file
      end
      assert_equal "Composeファイルが見つかりません", error.message
    end
  end

  def test_rejects_multiple_compose_files
    Dir.mktmpdir do |root|
      File.write(File.join(root, "compose.yaml"), "services: {}\n")
      File.write(File.join(root, "docker-compose.yml"), "services: {}\n")

      error = assert_raises(ComposePilot::ComposeError) do
        ComposePilot::ProjectLocator.new(container_root: root).compose_file
      end
      assert_match(/Composeファイルが複数見つかりました/, error.message)
    end
  end
end
