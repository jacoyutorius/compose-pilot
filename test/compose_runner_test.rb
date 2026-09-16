# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "tmpdir"
require_relative "../lib/compose_runner"

class ComposeRunnerTest < Minitest::Test
  Status = Struct.new(:ok) do
    def success?
      ok
    end
  end

  def test_path_within_project_root
    Dir.mktmpdir do |root|
      runner = build_runner(root)

      assert runner.path_within?(File.join(root, "sample"))
      refute runner.path_within?("#{root}-other/sample")
      refute runner.path_within?(File.join(root, "..", "outside"))
    end
  end

  def test_empty_selection_expands_to_all_services_except_compose_pilot
    with_runner do |runner|
      stub_config do
        command = runner.action_command(action: "stop", services: [])

        assert_equal ["stop", "web", "db"], command.last(3)
        assert_includes command, "sample-project"
        refute_includes command.last(3), "compose-pilot"
      end
    end
  end

  def test_self_service_is_rejected_by_default
    with_runner do |runner|
      stub_config do
        error = assert_raises(ComposePilot::ComposeError) do
          runner.action_command(action: "restart", services: ["compose-pilot"])
        end

        assert_equal "Compose Pilot自身は操作できません", error.message
      end
    end
  end

  def test_self_service_can_be_selected_when_explicitly_enabled
    with_runner(allow_self_operation: true) do |runner|
      stub_config do
        command = runner.action_command(action: "restart", services: ["compose-pilot"])

        assert_equal ["restart", "compose-pilot"], command.last(2)
      end
    end
  end

  def test_remove_targets_services_instead_of_project_down
    with_runner do |runner|
      stub_config do
        command = runner.action_command(action: "remove", services: ["web"])

        assert_equal ["rm", "--stop", "--force", "web"], command.last(4)
        refute_includes command, "down"
      end
    end
  end

  def test_unknown_service_is_rejected
    with_runner do |runner|
      stub_config do
        error = assert_raises(ComposePilot::ComposeError) do
          runner.action_command(action: "stop", services: ["unknown"])
        end

        assert_match(/存在しないサービス/, error.message)
      end
    end
  end

  def test_logs_without_selection_exclude_compose_pilot
    with_runner do |runner|
      stub_config do
        command = runner.logs_command

        assert_equal ["web", "db"], command.last(2)
        refute_includes command, "compose-pilot"
        refute_includes command, "--follow"
      end
    end
  end

  def test_logs_can_target_a_single_service
    with_runner do |runner|
      stub_config do
        command = runner.logs_command(service: "web")

        assert_equal "web", command.last
        refute_includes command, "db"
        refute_includes command, "compose-pilot"
        refute_includes command, "--follow"
      end
    end
  end

  def test_logs_reject_unknown_service
    with_runner do |runner|
      stub_config do
        error = assert_raises(ComposePilot::ComposeError) do
          runner.logs_command(service: "unknown")
        end

        assert_match(/存在しないサービス/, error.message)
      end
    end
  end

  def test_relative_host_project_root_is_rejected
    Dir.mktmpdir do |root|
      error = assert_raises(ComposePilot::ComposeError) do
        ComposePilot::ComposeRunner.new(
          container_root: root,
          host_root: "relative/path",
          generated_dir: File.join(root, "generated"),
          compose_file: "compose.yaml",
          project_name: "sample-project",
          self_service: "compose-pilot"
        )
      end

      assert_match(/絶対パス/, error.message)
    end
  end

  def test_project_marks_self_service_as_unselectable
    with_runner do |runner|
      stub_config do
        project = runner.project
        self_service = project.fetch(:services).find { |service| service.fetch(:self) }

        assert_equal "sample-project", project.fetch(:name)
        assert_equal "compose-pilot", self_service.fetch(:name)
        refute self_service.fetch(:selectable)
      end
    end
  end

  def test_project_exposes_browser_open_configuration
    with_runner do |runner|
      stub_config do
        project = runner.project
        web = project.fetch(:services).find { |service| service.fetch(:name) == "web" }

        assert_equal({ targetPort: 3000, scheme: "https", path: "/admin" }, web.fetch(:open))
      end
    end
  end

  def test_invalid_browser_open_scheme_is_rejected
    with_runner do |runner|
      config = compose_config
      config["services"]["web"]["labels"]["compose-pilot.open-scheme"] = "file"
      stub_config(config) do
        error = assert_raises(ComposePilot::ComposeError) { runner.project }

        assert_match(/httpまたはhttps/, error.message)
      end
    end
  end

  private

  def with_runner(allow_self_operation: false)
    Dir.mktmpdir do |root|
      File.write(File.join(root, "compose.yaml"), "services: {}\n")
      yield build_runner(root, allow_self_operation: allow_self_operation)
    end
  end

  def build_runner(root, allow_self_operation: false)
    ComposePilot::ComposeRunner.new(
      container_root: root,
      host_root: "/Users/example/sample",
      generated_dir: File.join(root, "generated"),
      compose_file: "compose.yaml",
      project_name: "sample-project",
      self_service: "compose-pilot",
      allow_self_operation: allow_self_operation
    )
  end

  def compose_config
    {
      "name" => "sample-project",
      "services" => {
        "web" => {
          "labels" => {
            "compose-pilot.open-port" => "3000",
            "compose-pilot.open-scheme" => "https",
            "compose-pilot.open-path" => "/admin"
          }
        },
        "db" => {},
        "compose-pilot" => {}
      }
    }
  end

  def stub_config(config = compose_config)
    Open3.stub(:capture3, [JSON.generate(config), "", Status.new(true)]) { yield }
  end
end
