# As Blackbook's migration of 2026-11-23 makes it.
ActiveRecord::Base.connection.instance_eval do
  drop_table :users, if_exists: true
  create_table(:users) { |t| t.string :email, null: false }
  create_table :mcp_tokens do |t|
    t.references :user, null: false, foreign_key: true
    t.string :machine, null: false
    t.string :digest, null: false, index: { unique: true }
    t.string :scopes, null: false, array: true, default: []
    t.datetime :expires_at, null: false
    t.datetime :revoked_at
    t.datetime :last_used_at

    t.timestamps
  end
end
