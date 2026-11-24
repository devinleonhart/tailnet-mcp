require "mcp"
require "rails"
require "active_support/all"
require "active_record/railtie"
require "action_controller/railtie"
require_relative "tailnet_mcp/version"
require_relative "tailnet_mcp/configuration"
require_relative "tailnet_mcp/limits"
require_relative "tailnet_mcp/tool_set"
require_relative "tailnet_mcp/engine"

# Serves MCP from a Rails application. See the README.
module TailnetMcp
  # A message for the caller.
  class Refused < StandardError; end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
    end

    def tools
      configuration.tool_sets.call.flat_map(&:tools)
    end
  end
end
