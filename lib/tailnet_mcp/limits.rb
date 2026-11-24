module TailnetMcp
  # Counts in memory, so it suits one process. Each window starts with its first count.
  module Limits
    WINDOW = 1.minute
    STORE = ActiveSupport::Cache::MemoryStore.new(size: 4.megabytes)

    module_function

    def call_allowed?(token)
      increment("call/#{token.id}") <= TailnetMcp.configuration.calls
    end

    def failures_exceeded?(address)
      STORE.read("failure/#{address}").to_i >= TailnetMcp.configuration.failures
    end

    def count_failure(address)
      increment("failure/#{address}")
    end

    def reset
      STORE.clear
    end

    def increment(key)
      STORE.increment(key, 1, expires_in: WINDOW)
    end
  end
end
