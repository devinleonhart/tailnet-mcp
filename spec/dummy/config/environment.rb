require_relative "application"
ENV["DATABASE_URL"] ||= "sqlite3::memory:"
Dummy.initialize!
Dummy.routes.draw do
  match "mcp", to: "tailnet_mcp/endpoint#handle", via: :all, format: false
  get "plain", to: "plain#show"
end
