# tailnet_mcp

Serves [MCP](https://modelcontextprotocol.io) from a Rails application to machines on a private
network, such as a tailnet. Each machine has its own token, with scopes and an expiry.

## Features

```ruby
# Gemfile
gem "tailnet_mcp", github: "devinleonhart/tailnet-mcp", ref: "<commit>"

# config/routes.rb
match "mcp", to: "tailnet_mcp/endpoint#handle", via: :all, format: false

# config/initializers/tailnet_mcp.rb
TailnetMcp.configure do |config|
  config.name = "my-application"
  config.token_prefix = "mya"
  config.host = ENV["MCP_HOST"].presence     # without it, the endpoint does not exist
  config.tool_sets = -> { [ThingTools] }
  config.context = ->(token) { token }       # what tools get besides their input
end
```

```ruby
module ThingTools
  extend TailnetMcp::ToolSet

  tool("get_thing", :read, "Get a thing", { id: id }) do |input, context|
    Thing.find_by(id: input[:id]) || raise(TailnetMcp::Refused, "Thing not found")
  end
end
```

`bin/rails tailnet_mcp:install:migrations` copies the migration of the token table.

```bash
bin/rails mcp:tokens:issue MACHINE=<name> SCOPES=read,write DAYS=90   # prints the token once
bin/rails mcp:tokens:list
bin/rails mcp:tokens:revoke ID=<id>
```

### Tokens of a user

An application may tie tokens to a record of its own, in a column that it adds to the table:

```ruby
ActiveSupport.on_load(:tailnet_mcp_token) { belongs_to :user }

TailnetMcp.configure do |config|
  config.context = ->(token) { token.user }
  config.token_attributes = lambda do |variables|
    { user: User.find_by(email: variables["OWNER"]) || raise(TailnetMcp::Refused, "No such user") }
  end
  config.list_facts = ->(token) { [token.user.email] }
  config.log_facts = ->(token) { { user: token.user_id } }
end
```

Scopes may also be in a PostgreSQL array column, for tables made before the gem.

What it guarantees:

- Only `config.host` is answered, read from the Host header itself, since forwarding headers can be
  sent by anyone. A foreign Origin is refused.
- Only a live token authorizes a request. Its text is never stored or logged.
- A token is offered, and may call, only the tools of its scopes.
- Calls are limited for each token, and failures for each address, in memory: use one process.
- The log has one line for a request, without arguments.

The application behind a proxy should also keep `/mcp` from its public site, and exclude it from
`config.host_authorization`, since the endpoint checks its own host.

`require "tailnet_mcp/rspec"` gives the shared examples `a tailnet MCP endpoint`.

## Development

Needs Docker.

```bash
docker build -t tailnet-mcp .
docker run --rm tailnet-mcp bin/ci   # everything CI checks; POSTGRES_URL adds a run on PostgreSQL
```

## Deployment

There is no release. An application pins a commit in its Gemfile and moves the pin to take a change.

## Architecture

```
app/controllers/tailnet_mcp/   # The endpoint
app/models/tailnet_mcp/        # The token
lib/tailnet_mcp/               # Configuration, tool sets, limits, and the shared examples
```
