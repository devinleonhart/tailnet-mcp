require_relative "lib/tailnet_mcp/version"

Gem::Specification.new do |spec|
  spec.name = "tailnet_mcp"
  spec.version = TailnetMcp::VERSION
  spec.authors = ["Devin Leonhart"]
  spec.summary = "Serves MCP from a Rails application to machines on a private network, each with its own token."
  spec.homepage = "https://github.com/devinleonhart/tailnet-mcp"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0.10"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.files = Dir["{app,db,lib}/**/*", "LICENSE", "README.md"]

  spec.add_dependency "mcp", "~> 1.11"
  spec.add_dependency "rails", "~> 8.1", ">= 8.1.4.1"
end
