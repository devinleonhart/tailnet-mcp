require "tailnet_mcp"

# Helpers and shared examples for request specs, here and in applications.
#
#   include_context "with tailnet MCP"
#   it_behaves_like "a tailnet MCP endpoint", tool: "list_things", page: "/things"
#
# The tool needs the read scope and no input. The page belongs to the application.
module TailnetMcp
  module RSpecHelpers
    HOST = "server.example.ts.net".freeze

    def issue_token(*scopes, machine: "laptop")
      Token.issue!(machine:, scopes: scopes.presence || ["read"])
    end

    def mcp_post(body, token: nil, host: HOST, headers: {})
      all = { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream", "Host" => host }
      all["Authorization"] = "Bearer #{token}" if token
      post "/mcp", params: body.is_a?(String) ? body : body.to_json, headers: all.merge(headers)
    end

    def mcp_request(method, params = {}, **)
      mcp_post({ jsonrpc: "2.0", id: 1, method:, params: }, **)
      response.parsed_body
    end

    def call_tool(name, arguments = {}, token:)
      mcp_request("tools/call", { name:, arguments: }, token:)
    end

    # The text of a successful call.
    def tool_text(name, arguments = {}, token:)
      body = call_tool(name, arguments, token:)
      expect(body["error"] || body.dig("result", "isError")).to be_blank, body.inspect
      body.dig("result", "content").sole.fetch("text")
    end

    def tool_data(...)
      JSON.parse(tool_text(...))
    end

    # The message of a refused call, whether the tool or the protocol refused it.
    def tool_error(name, arguments = {}, token:)
      body = call_tool(name, arguments, token:)
      return body.dig("error", "message") if body["error"]

      expect(body.dig("result", "isError")).to be(true), body.inspect
      body.dig("result", "content").sole.fetch("text")
    end

    def tool_names(token)
      mcp_request("tools/list", token:).dig("result", "tools").pluck("name")
    end
  end
end

RSpec.shared_context "with tailnet MCP" do
  include TailnetMcp::RSpecHelpers
  include ActiveSupport::Testing::TimeHelpers

  let(:mcp_list) { { jsonrpc: "2.0", id: 1, method: "tools/list" } }
  let(:token) { issue_token("read", "write", "delete") }
  let(:reader) { issue_token("read") }
  let(:writer) { issue_token("read", "write") }

  before do
    allow(TailnetMcp.configuration).to receive(:host).and_return(TailnetMcp::RSpecHelpers::HOST)
    TailnetMcp::Limits.reset
  end

  def mcp_status(body = mcp_list, **)
    mcp_post(body, **)
    response.status
  end
end

RSpec.shared_examples "a tailnet MCP endpoint" do |tool:, page:|
  let(:mcp_host) { TailnetMcp::RSpecHelpers::HOST }

  describe "authentication" do
    it "refuses anything but a live token, with one answer" do
      expired = issue_token
      TailnetMcp::Token.authenticate(expired).update!(expires_at: 1.second.ago)
      revoked = issue_token
      TailnetMcp::Token.authenticate(revoked).revoke!
      headers = [nil, "", "Bearer", "Bearer ", "Bearer wrong", "Bearer #{expired}", "Bearer #{revoked}", reader,
                 "Basic #{reader}", "Token #{reader}", "Bearer  #{reader}", "Bearer #{reader} x", "Bearer \xFF",
                 "Bearer other_#{reader.split('_', 2).last}"]

      answers = headers.map do |value|
        mcp_post(mcp_list, headers: value ? { "Authorization" => value } : {})
        [response.status, response.body, response.headers["WWW-Authenticate"]]
      end

      expect(answers.uniq).to eq([[401, '{"error":"Unauthorized"}', "Bearer"]])
    end

    it "accepts a live token, the scheme in any case" do
      expect(mcp_status(token: reader)).to eq(200)
      mcp_post(mcp_list, headers: { "Authorization" => "bearer #{reader}" })
      expect(response).to have_http_status(:ok)
    end

    it "does not accept a token in the address or the body" do
      post "/mcp?token=#{reader}&access_token=#{reader}", params: mcp_list.merge(token: reader).to_json,
                                                          headers: { "Host" => mcp_host }

      expect(response).to have_http_status(:unauthorized)
    end

    it "records the last use" do
      freeze_time do
        mcp_status(token: reader)

        expect(TailnetMcp::Token.authenticate(reader).last_used_at).to eq(Time.current)
      end
    end
  end

  describe "host and origin" do
    it "answers only its host" do
      ["public.example", "localhost", "127.0.0.1", "#{mcp_host}.evil.example", "x#{mcp_host}", "evil.example:8443"]
        .each { |other| expect(mcp_status(host: other, token: reader)).to eq(403), other }
      expect(mcp_status(host: "#{mcp_host}:8443", token: reader)).to eq(200)
      expect(mcp_status(host: mcp_host.upcase, token: reader)).to eq(200)
    end

    it "does not believe forwarding headers" do
      { "X-Forwarded-Host" => mcp_host, "X-Forwarded-Server" => mcp_host, "X-Original-Host" => mcp_host,
        "Forwarded" => "host=#{mcp_host}" }.each do |name, value|
        expect(mcp_status(host: "public.example", token: reader, headers: { name => value })).to eq(403)
      end
    end

    it "refuses foreign origins" do
      ["https://evil.example", "null", "http://localhost", "nonsense", "http://[", "file://",
       "https://#{mcp_host}.evil.example"].each do |origin|
        expect(mcp_status(token: reader, headers: { "Origin" => origin })).to eq(403), origin
      end
      expect(mcp_status(token: reader, headers: { "Origin" => "https://#{mcp_host}:8443" })).to eq(200)
    end

    it "does not exist without a configured host" do
      [nil, ""].each do |none|
        allow(TailnetMcp.configuration).to receive(:host).and_return(none)

        expect(mcp_status(token: reader)).to eq(404)
        expect(mcp_status(host: "", token: reader)).to eq(404)
      end
    end

    it "takes only POST" do
      headers = { "Host" => mcp_host, "Authorization" => "Bearer #{reader}" }
      %i[get delete put patch options head].each do |verb|
        public_send(verb, "/mcp", headers:)

        expect(response).to have_http_status(:method_not_allowed)
        expect(response.headers["Allow"]).to eq("POST")
      end
    end
  end

  describe "limits" do
    it "limits calls for each token" do
      freeze_time
      limit = TailnetMcp.configuration.calls
      expect(Array.new(limit) { mcp_status(token: reader) }.uniq).to eq([200])
      expect(mcp_status(token: reader)).to eq(429)
      expect(mcp_status(token: writer)).to eq(200)
      travel 61.seconds
      expect(mcp_status(token: reader)).to eq(200)
    end

    it "limits failures for each address" do
      freeze_time
      expect(Array.new(TailnetMcp.configuration.failures) { mcp_status(token: "wrong") }.uniq).to eq([401])
      expect(mcp_status(token: "wrong")).to eq(429)
      expect(mcp_status(token: "wrong", headers: { "REMOTE_ADDR" => "203.0.113.9" })).to eq(401)
      travel 61.seconds
      expect(mcp_status(token: "wrong")).to eq(401)
    end

    it "does not count successes as failures" do
      (TailnetMcp.configuration.failures + 5).times { mcp_status(token: reader) }

      expect(mcp_status(token: "wrong")).to eq(401)
    end
  end

  describe "bodies" do
    it "refuses malformed ones without an exception" do
      ["", "{", "null", "3", '"x"', "[]", "[1]", "{}", '{"jsonrpc":"2.0"}', "\xFF", ("[" * 2000)].each do |body|
        mcp_post(body, token: reader)

        expect(response.status).to be_between(200, 499), body
        expect(response.media_type).to eq("application/json")
        expect(response.parsed_body.to_s).not_to include("Exception", "app/")
      end
    end

    it "refuses large ones" do
      expect(mcp_status("x" * (4.megabytes + 1), token: reader)).to eq(413)
    end
  end

  describe "log" do
    let(:log) { StringIO.new }

    around do |example|
      kept = [Rails.logger, ActionController::Base.logger, ActiveRecord::Base.logger]
      Rails.logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(log, level: :info))
      ActionController::Base.logger = ActiveRecord::Base.logger = Rails.logger
      example.run
    ensure
      Rails.logger, ActionController::Base.logger, ActiveRecord::Base.logger = kept
    end

    def mcp_lines
      log.string.lines.grep(/\bmcp token=/)
    end

    it "has one line for a call, with its facts" do
      record = TailnetMcp::Token.authenticate(reader)
      call_tool(tool, token: reader)

      expect(mcp_lines.sole).to match(/mcp token=#{record.id} machine="laptop" call=#{tool} outcome=ok duration=\d+ms$/)
    end

    it "tells refusals and errors apart, and shows no text of the caller's" do
      call_tool("nothing\nmcp token=1", {}, token: reader)
      mcp_request("tools/list", token: reader)
      mcp_request("made/up", token: reader)
      mcp_status(token: "wrong")
      mcp_status(host: "evil.example", token: reader)

      expect(mcp_lines.map { |line| [line[/call=(\S+)/, 1], line[/outcome=(\S+)/, 1]] })
        .to eq([%w[unknown error], %w[tools/list ok], %w[unknown error], %w[- 401], %w[- 403]])
    end

    it "keeps machine names on one line" do
      call_tool(tool, token: issue_token(machine: "a\nmcp token=99"))

      expect(mcp_lines.size).to eq(1)
    end

    it "holds no token, digest or argument" do
      call_tool(tool, { secret: "argument-value" }, token: reader)
      call_tool(tool, {}, token: reader)
      mcp_status("{\"broken\": \"argument-value\"", token: reader)
      mcp_status(token: "#{reader}x")
      mcp_status(token: reader.chop)
      mcp_status(token: reader, host: "evil.example")

      expect(mcp_lines.size).to eq(6)
      expect(log.string).not_to include(reader.split("_", 2).last.chop, TailnetMcp::Token.authenticate(reader).digest)
      expect(log.string).not_to include("argument-value")
    end
  end

  it "sets no cookie, also when it refuses" do
    [{ token: reader }, {}, { host: "evil.example" }].each do |options|
      mcp_status(**options)

      expect(response.headers["Set-Cookie"]).to be_nil
    end
  end

  it "offers every tool to a token with every scope, and fewer to narrower ones" do
    all = TailnetMcp.tools

    expect(tool_names(token)).to match_array(all.map(&:name))
    expect(tool_names(writer)).to match_array(all.reject { |one| one.scope == :delete }.map(&:name))
    expect(tool_names(reader)).to match_array(all.select { |one| one.scope == :read }.map(&:name))
  end

  it "refuses a tool outside the scope" do
    TailnetMcp.tools.reject { |one| one.scope == :read }.each do |one|
      expect(tool_error(one.name, token: reader)).to be_present
    end
    TailnetMcp::Token.authenticate(reader).update_columns(scopes: []) # rubocop:disable Rails/SkipsModelValidations
    expect(tool_names(reader)).to eq([])
    expect(tool_error(tool, token: reader)).to be_present
  end

  it "leaves the rest of the application as it was" do
    get page, headers: { "Authorization" => "Bearer #{reader}" }
    with_token = [response.status, response.body.size.positive?]
    get page

    expect([response.status, response.body.size.positive?]).to eq(with_token)
  end
end
