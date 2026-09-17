# frozen_string_literal: true

require "minitest/autorun"
require "rbconfig"

require_relative "../lib/command_body"

class CommandBodyTest < Minitest::Test
  def test_runs_commands_in_order
    body = ComposePilot::CommandBody.new([
      [RbConfig.ruby, "-e", "puts 'first'"],
      [RbConfig.ruby, "-e", "puts 'second'"]
    ])

    output = +""
    body.each { |chunk| output << chunk }

    assert_operator output.index("first"), :<, output.index("second")
    assert_includes output, "完了しました"
  end

  def test_stops_after_failed_command
    body = ComposePilot::CommandBody.new([
      [RbConfig.ruby, "-e", "exit 1"],
      [RbConfig.ruby, "-e", "puts 'should-not-run'"]
    ])

    output = +""
    body.each { |chunk| output << chunk }

    assert_includes output, "コマンドの実行に失敗しました"
    refute_includes output, "should-not-run"
  end
end
