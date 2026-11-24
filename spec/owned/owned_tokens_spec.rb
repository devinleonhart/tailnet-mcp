# The table as Blackbook and Chronicler made it: tokens of a user, and scopes in an array.
# It runs alone, in the second dummy application (see bin/ci).
RSpec.describe "Tokens of a user", if: ENV.key?("OWNED"), type: :request do
  include_context "with tailnet MCP"

  let(:model) { TailnetMcp::Token }
  let(:user) { User.create!(email: "a@example.com") }
  let(:other) { User.create!(email: "b@example.com") }
  let(:reader) { model.issue!(machine: "laptop", user:) }

  def sql(text) = ActiveRecord::Base.connection.select_all(text).to_a

  def run_task(name, variables = {})
    require "rake"
    kept = ENV.to_h
    Rails.application.load_tasks unless Rake::Task.task_defined?("mcp:tokens:list")
    out = StringIO.new
    err = StringIO.new
    $stdout = out
    $stderr = err
    ENV.update(variables)
    Rake::Task[name].reenable
    Rake::Task[name].invoke
    [out.string, err.string, true]
  rescue SystemExit => error
    [out.string, err.string + error.message, error.success?]
  ensure
    $stdout = STDOUT
    $stderr = STDERR
    ENV.replace(kept)
  end

  it "need a user" do
    expect { model.issue!(machine: "laptop") }.to raise_error(ActiveRecord::RecordInvalid, /User must exist/)
  end

  it "keep their scopes in the array" do
    model.issue!(machine: "laptop", user:, scopes: %w[delete read write read])

    expect(sql("select scopes::text as s, array_length(scopes, 1) as n from mcp_tokens"))
      .to eq([{ "s" => "{read,write,delete}", "n" => 3 }])
    expect(model.first.scopes).to eq(%w[read write delete])
    expect(model.columns_hash["scopes"]).to be_array
  end

  it "are read as production holds them" do
    text = "tst_#{'a' * 43}"
    sql(<<~SQL.squish)
      insert into mcp_tokens (user_id, machine, digest, scopes, expires_at, created_at, updated_at)
      values (#{user.id}, 'desktop', '#{Digest::SHA256.hexdigest(text)}', '{read,write}',
              now() + interval '1 day', now(), now())
      returning id
    SQL
    token = model.authenticate(text)

    expect(token).to have_attributes(user:, machine: "desktop", scopes: %w[read write])
    expect([token.allows?(:write), token.allows?(:delete)]).to eq([true, false])
  end

  it "are stored as the applications' own model stored them" do
    old = Class.new(ActiveRecord::Base) do
      self.table_name = "mcp_tokens"
    end
    text = model.issue!(machine: " laptop ", user:, scopes: %w[write read], days: 30)
    columns = "user_id, machine, scopes::text as scopes, revoked_at, last_used_at"
    new_row = sql("select #{columns} from mcp_tokens").sole
    old.create!(user_id: user.id, machine: "laptop", scopes: %w[read write], digest: "x",
                expires_at: 30.days.from_now)

    expect(sql("select #{columns} from mcp_tokens where digest = 'x'").sole).to eq(new_row)
    expect(old.find_by(digest: Digest::SHA256.hexdigest(text)).scopes).to eq(%w[read write])
  end

  it "refuse scopes as before" do
    { ["admin"] => /unknown/, ["write"] => /read/, [] => /read/ }.each do |scopes, message|
      expect { model.issue!(machine: "l", user:, scopes:) }.to raise_error(ActiveRecord::RecordInvalid, message)
    end
  end

  it "notice changed scopes" do
    token = model.authenticate(reader)
    token.scopes << "write"
    token.save!

    expect(model.find(token.id).scopes).to eq(%w[read write])
  end

  it "give tools their own user" do
    mine = reader
    theirs = model.issue!(machine: "laptop", user: other)

    expect(tool_data("show_context", token: mine)).to eq("email" => "a@example.com")
    expect(tool_data("show_context", token: theirs)).to eq("email" => "b@example.com")
  end

  it "offer tools by scope" do
    writer = model.issue!(machine: "laptop", user:, scopes: %w[read write])

    expect(tool_names(reader)).not_to include("add_thing")
    expect(tool_names(writer)).to include("add_thing").and not_include("delete_thing")
  end

  it "are issued for the user that the command names" do
    user
    out, err, success = run_task("mcp:tokens:issue", "MACHINE" => "desktop", "OWNER" => "a@example.com")

    expect(success).to be(true)
    expect(out.lines.size).to eq(1)
    expect(model.authenticate(out.chomp)).to have_attributes(machine: "desktop", user:)
    expect(err).to include("desktop").and not_include(out.chomp)
  end

  it "are not issued without a user" do
    [{}, { "OWNER" => "nobody@example.com" }].each do |variables|
      out, err, success = run_task("mcp:tokens:issue", { "MACHINE" => "desktop" }.merge(variables))

      expect([out, success]).to eq(["", false])
      expect(err).to include("No user has the email in OWNER")
    end
    expect(model.count).to eq(0)
  end

  it "are listed with their user, and without their text" do
    reader
    out, = run_task("mcp:tokens:list")

    expect(out.lines.sole).to include("a@example.com", "laptop", "read")
    expect(out).not_to include(reader, model.first.digest)
  end

  it "are revoked" do
    run_task("mcp:tokens:revoke", "ID" => model.authenticate(reader).id.to_s)

    expect(mcp_status(token: reader)).to eq(401)
  end

  it_behaves_like "a tailnet MCP endpoint", tool: "list_things", page: "/plain" do
    def issue_token(*scopes, machine: "laptop")
      model.issue!(machine:, user:, scopes: scopes.presence || ["read"])
    end

    let(:reader) { issue_token("read") }
    let(:writer) { issue_token("read", "write") }
  end

  it "add the application's facts to the log, on one line" do
    log = StringIO.new
    kept = Rails.logger
    Rails.logger = Logger.new(log)
    call_tool("list_things", token: reader)
    mcp_status(token: "wrong")

    lines = log.string.lines.grep(/mcp token=/)
    expect(lines.first).to match(/machine="laptop" user=#{user.id} call=list_things outcome=ok/)
    expect(lines.last).to include("token=- machine=- call=- outcome=401")
    expect(log.string).not_to include(reader)
  ensure
    Rails.logger = kept
  end
end
