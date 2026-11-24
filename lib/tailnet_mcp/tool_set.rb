module TailnetMcp
  # Extend a module with this to define tools in it.
  #
  #   tool("get_thing", :read, "Get a thing", { id: id }) { |input, context| ... }
  #
  # The block returns text, or data that becomes JSON. It may raise Refused.
  module ToolSet
    Tool = Data.define(:name, :scope, :definition)

    def tools
      @tools ||= []
    end

    def tool(name, scope, description, properties = {}, required: properties.keys, &block)
      set = self
      schema = { type: "object", properties:, required: required.map(&:to_s), additionalProperties: false }
      definition = MCP::Tool.define(
        name:, description:, annotations: annotations_for(scope), input_schema: schema
      ) { |server_context:, **input| set.respond { block.call(input, server_context[:context]) } }
      tools << Tool.new(name:, scope:, definition:)
    end

    def annotations_for(scope)
      { read_only_hint: scope == :read, destructive_hint: scope == :delete, open_world_hint: false }
    end

    def id = { type: "integer", minimum: 1 }
    def text = { type: "string", maxLength: 255 }
    def flag = { type: "boolean" }

    # An application may override how results and errors are worded.
    def respond
      data = yield
      result(data.is_a?(String) ? data : JSON.generate(data))
    rescue Refused => error
      result(error.message, error: true)
    rescue ActiveRecord::RecordInvalid => error
      result(error.record.errors.full_messages.join(", "), error: true)
    rescue StandardError => error
      # Its message may hold what was sent.
      Rails.logger.error("mcp tool failed: #{error.class} at #{error.backtrace&.first}")
      result("Internal error", error: true)
    end

    def result(text, error: false)
      MCP::Tool::Response.new([{ type: "text", text: }], error:)
    end
  end
end
