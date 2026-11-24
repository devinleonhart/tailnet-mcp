require "bundler/setup"
require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "tailnet_mcp"

# No Active Storage, mail, sessions, views or users.
class Dummy < Rails::Application
  config.root = File.expand_path("..", __dir__)
  config.load_defaults 8.1
  config.eager_load = true
  config.api_only = true
  config.secret_key_base = "x" * 64
  config.active_support.deprecation = :raise
  config.active_record.maintain_test_schema = false
  config.action_dispatch.show_exceptions = :rescuable
  config.cache_store = :null_store
  config.logger = Logger.new(nil)
  config.hosts.clear
end

# Tools of every scope, and one that shows its context.
module Things
  extend TailnetMcp::ToolSet

  def self.list = @list ||= ["one"]

  tool("list_things", :read, "List things") { list }
  tool("show_context", :read, "Show the context") { |_, context| context }
  tool("say", :read, "Say words", { words: text }) { |input, _| input[:words] }
  tool("add_thing", :write, "Add a thing", { name: text }) do |input, _|
    raise TailnetMcp::Refused, "Thing exists" if list.include?(input[:name])

    list << input[:name]
  end
  tool("add_token", :write, "Add an invalid record") { TailnetMcp::Token.create!(machine: "") }
  tool("delete_thing", :delete, "Delete a thing", { name: text, quiet: flag, count: id },
       required: [:name]) do |input, _|
    list.delete(input[:name])
    { deleted: true }
  end
end

# As Blackbook and Chronicler have it: each token acts as a user.
if ENV["OWNED"]
  class User < ActiveRecord::Base; end

  ActiveSupport.on_load(:tailnet_mcp_token) { belongs_to :user }
end

class PlainController < ActionController::API
  def show = head(:no_content)
end

TailnetMcp.configure do |config|
  config.name = "dummy"
  config.token_prefix = "tst"
  config.tool_sets = -> { [Things] }
  config.context = ->(token) { { machine: token.machine } }
end

if ENV["OWNED"]
  TailnetMcp.configure do |config|
    config.context = ->(token) { { email: token.user.email } }
    config.token_attributes = lambda do |variables|
      { user: User.find_by(email: variables["OWNER"]) || raise(TailnetMcp::Refused, "No user has the email in OWNER") }
    end
    config.list_facts = ->(token) { [token.user.email] }
    config.log_facts = ->(token) { { user: token.user_id } }
  end
end
