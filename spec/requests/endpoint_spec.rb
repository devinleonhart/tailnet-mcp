RSpec.describe "Endpoint" do
  include_context "with tailnet MCP"

  it_behaves_like "a tailnet MCP endpoint", tool: "list_things", page: "/plain"

  it "initializes" do
    result = mcp_request("initialize", { protocolVersion: "2025-06-18", capabilities: {},
                                         clientInfo: { name: "spec", version: "1" } }, token: reader)["result"]

    expect(result["serverInfo"]).to include("name" => "dummy", "version" => "1.0.0")
    expect(response.media_type).to eq("application/json")
    expect(response.headers.to_h.keys.map(&:downcase)).not_to include("mcp-session-id")
  end

  it "accepts notifications" do
    mcp_post({ jsonrpc: "2.0", method: "notifications/initialized" }, token: reader)

    expect(response).to have_http_status(:accepted)
  end

  it "gives tools the application's context" do
    expect(tool_data("show_context", token: reader)).to eq("machine" => "laptop")
  end

  it "survives params that are not an object" do
    mcp_post({ jsonrpc: "2.0", id: 1, method: "tools/call", params: [1] }, token: reader)

    expect(response.parsed_body["error"]).to be_present
  end
end
