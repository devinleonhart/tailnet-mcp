# tailnet_mcp

Read README.md for use and commands. A Rails engine, on Rails 8.1 and Ruby 4.0, over the `mcp` gem.

- `bin/ci` runs in the image of the Dockerfile and needs `POSTGRES_URL`. It runs the specs three times: on SQLite,
  on PostgreSQL, and with tokens tied to a user (`OWNED=1`, `spec/owned`).
- `spec/dummy` is the application the specs run in.
- What the README guarantees must stay true: only the configured host is answered, read from the Host header
  itself; a token's text is never stored or logged; a token sees and calls only the tools of its scopes.
- Blackbook, Chronicler and the Emote Generator use the gem, and run `lib/tailnet_mcp/rspec.rb` against their own
  endpoints. A change to those shared examples is a change for all three.
- To release, raise `lib/tailnet_mcp/version.rb`. On `master`, CI tags `v<version>` once. Each application then
  moves its pin to the tag. The gem is not on RubyGems.
