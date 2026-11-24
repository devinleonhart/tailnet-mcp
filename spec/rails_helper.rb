require "simplecov"

SimpleCov.start do
  enable_coverage :branch
  skip "/spec/"
  # The gemspec loads it before coverage starts.
  skip "lib/tailnet_mcp/version.rb"
  cover "{app,lib}/**/*.rb"
  minimum_coverage line: 100 if ENV["CI"] && !ENV["OWNED"]
end

ENV["RAILS_ENV"] = "test"
require_relative "dummy/config/environment"
require "rspec/rails"
require "tailnet_mcp/rspec"

ActiveRecord::Schema.verbose = false
ActiveRecord::Migration.suppress_messages do
  ActiveRecord::Base.connection.drop_table(:mcp_tokens, if_exists: true)
  require_relative "owned/schema" if ENV["OWNED"]
  ActiveRecord::MigrationContext.new(File.expand_path("../db/migrate", __dir__)).migrations.each do |migration|
    next if ENV["OWNED"]

    migration.migrate(:up)
  end
end

RSpec::Matchers.define_negated_matcher :not_include, :include

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.disable_monkey_patching!
  config.include ActiveSupport::Testing::TimeHelpers
  config.order = :random
  # With OWNED, only the specs of the second table.
  config.filter_run_including(file_path: %r{spec/owned}) if ENV["OWNED"]
  Kernel.srand config.seed
end
