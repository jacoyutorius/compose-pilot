# frozen_string_literal: true

require "set"

module ComposePilot
  # 同じプロジェクトに対するCompose操作の多重実行を防止する。
  class OperationRegistry
    def initialize
      @active = Set.new
      @mutex = Mutex.new
    end

    def acquire(key)
      @mutex.synchronize do
        return false if @active.include?(key)

        @active.add(key)
        true
      end
    end

    def release(key)
      @mutex.synchronize { @active.delete(key) }
    end

    def active?(key)
      @mutex.synchronize { @active.include?(key) }
    end
  end
end
