# frozen_string_literal: true

require "json"
require "minitest/autorun"
require_relative "../lib/compose_runner"
require_relative "../lib/runtime_identity"

class RuntimeIdentityTest < Minitest::Test
  Status = Struct.new(:ok) do
    def success?
      ok
    end
  end

  def test_resolves_project_and_service_from_compose_labels
    inspect_data = [{
      "Config" => {
        "Labels" => {
          "com.docker.compose.project" => "sample",
          "com.docker.compose.service" => "compose-pilot"
        }
      }
    }]

    Open3.stub(:capture3, [JSON.generate(inspect_data), "", Status.new(true)]) do
      identity = ComposePilot::RuntimeIdentityResolver.new(container_id: "container-id").resolve

      assert_equal "sample", identity.project_name
      assert_equal "compose-pilot", identity.service_name
    end
  end

  def test_explicit_values_allow_running_outside_a_container
    identity = ComposePilot::RuntimeIdentityResolver.new(
      container_id: "",
      project_name: "sample",
      service_name: "pilot"
    ).resolve

    assert_equal "sample", identity.project_name
    assert_equal "pilot", identity.service_name
  end

  def test_missing_compose_labels_are_rejected
    inspect_data = [{ "Config" => { "Labels" => {} } }]

    Open3.stub(:capture3, [JSON.generate(inspect_data), "", Status.new(true)]) do
      error = assert_raises(ComposePilot::ComposeError) do
        ComposePilot::RuntimeIdentityResolver.new(container_id: "container-id").resolve
      end

      assert_equal "Composeプロジェクト名を識別できません", error.message
    end
  end
end
