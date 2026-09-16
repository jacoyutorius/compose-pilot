# frozen_string_literal: true

require "open3"
require "shellwords"

module ComposePilot
  # Rackレスポンスボディとして、コマンドを一度だけ実行して出力を逐次返す。
  class CommandBody
    def initialize(command, on_close: nil)
      @command = command.freeze
      @on_close = on_close
      @closed = false
      @mutex = Mutex.new
    end

    def each
      yield "$ #{Shellwords.shelljoin(@command)}\n\n"
      Open3.popen2e(*@command) do |_stdin, combined, wait_thread|
        combined.each_line { |line| yield line }
        status = wait_thread.value
        if status.success?
          yield "\n完了しました。\n"
        else
          yield "\nコマンドの実行に失敗しました（終了コード: #{status.exitstatus}）。\n"
        end
      end
    rescue StandardError => e
      yield "\nエラー: #{e.message}\n"
    ensure
      close
    end

    def close
      callback = @mutex.synchronize do
        next if @closed

        @closed = true
        @on_close
      end
      callback&.call
    end
  end
end
