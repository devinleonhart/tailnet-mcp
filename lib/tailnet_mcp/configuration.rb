module TailnetMcp
  class Configuration
    # The server's name and version, as clients see them.
    attr_accessor :name, :version

    # What a token's text begins with, so that a stray one can be recognized.
    attr_accessor :token_prefix

    # The only host the endpoint answers. Without it, the endpoint does not exist.
    attr_accessor :host

    # Gives the modules that extend ToolSet.
    attr_accessor :tool_sets

    # Gives what tools receive besides their input, from the token.
    attr_accessor :context

    # What a new token has besides, from the variables given to mcp:tokens:issue. May raise Refused.
    attr_accessor :token_attributes

    # What mcp:tokens:list shows of a token besides, as a list.
    attr_accessor :list_facts

    # What the log says of a token besides, by name.
    attr_accessor :log_facts

    # How many calls a token may make, and how many failures an address, in a minute.
    attr_accessor :calls, :failures

    def initialize
      @name = "rails"
      @version = "1.0.0"
      @token_prefix = "mcp"
      @tool_sets = -> { [] }
      @context = ->(token) { token }
      @token_attributes = ->(_variables) { {} }
      @list_facts = ->(_token) { [] }
      @log_facts = ->(_token) { {} }
      @calls = 120
      @failures = 20
    end
  end
end
