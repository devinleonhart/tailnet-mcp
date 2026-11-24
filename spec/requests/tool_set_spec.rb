RSpec.describe "Tool sets" do
  include_context "with tailnet MCP"

  after { Things.remove_instance_variable(:@list) if Things.instance_variable_defined?(:@list) }

  it "return JSON or text" do
    expect(tool_data("list_things", token: reader)).to eq(["one"])
    expect(tool_text("say", { words: "héllo" }, token: reader)).to eq("héllo")
  end

  it "refuse with a message" do
    expect(tool_data("add_thing", { name: "two" }, token: writer)).to eq(%w[one two])
    expect(tool_error("add_thing", { name: "two" }, token: writer)).to eq("Thing exists")
  end

  it "give a record's messages" do
    expect(tool_error("add_token", token: writer)).to include("Machine can't be blank")
  end

  it "hide other errors" do
    allow(Things).to receive(:list).and_raise(StandardError, "private detail")
    allow(Rails.logger).to receive(:error)

    expect(tool_error("list_things", token: reader)).to eq("Internal error")
    expect(Rails.logger).to have_received(:error).with(/failed: StandardError at /)
  end

  it "refuse input outside their schema" do
    [["say", {}], ["say", { words: 1 }], ["say", { words: "x" * 256 }], ["say", { words: "x", other: 1 }],
     ["list_things", { other: 1 }], ["delete_thing", { name: "one", count: 0 }]].each do |name, arguments|
      expect(tool_error(name, arguments, token:)).to be_present
    end
    expect(Things.list).to eq(["one"])
    expect(tool_data("delete_thing", { name: "one", quiet: true, count: 1 }, token:)).to eq("deleted" => true)
  end

  it "say what they do" do
    hints = mcp_request("tools/list", token:).dig("result", "tools").to_h do |tool|
      [tool["name"], tool["annotations"].values_at("readOnlyHint", "destructiveHint")]
    end

    expect(hints).to include("list_things" => [true, false], "add_thing" => [false, false],
                             "delete_thing" => [false, true])
  end
end
