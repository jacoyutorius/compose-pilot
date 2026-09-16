# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/compose_runner"

class ComposeRunnerTest < Minitest::Test
  def test_path_within_projects_root
    Dir.mktmpdir do |root|
      runner = ComposePilot::ComposeRunner.new(
        container_root: root,
        host_root: "/Users/example/projects",
        generated_dir: File.join(root, "generated")
      )

      assert runner.path_within?(File.join(root, "sample"))
      refute runner.path_within?("#{root}-other/sample")
      refute runner.path_within?(File.join(root, "..", "outside"))
    end
  end
end
