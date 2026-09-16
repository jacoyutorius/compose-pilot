# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/operation_registry"

class OperationRegistryTest < Minitest::Test
  def test_only_one_operation_can_acquire_a_project
    registry = ComposePilot::OperationRegistry.new

    assert registry.acquire("project-1")
    refute registry.acquire("project-1")
    assert registry.acquire("project-2")

    registry.release("project-1")
    assert registry.acquire("project-1")
  end
end
