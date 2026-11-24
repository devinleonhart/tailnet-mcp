module TailnetMcp
  # Lets one machine use MCP, within its scopes. The text is shown once, when issued;
  # only its digest is stored.
  class Token < ActiveRecord::Base
    SCOPES = %w[read write delete].freeze
    MAX_DAYS = 365

    # Scopes as a list, stored as text that every database has.
    class ScopeList < ActiveRecord::Type::String
      def cast(value)
        value.is_a?(String) ? value.split(",") : value
      end

      def deserialize(value)
        value.to_s.split(",")
      end

      def serialize(value)
        Array(value).join(",")
      end

      def changed_in_place?(stored, value)
        deserialize(stored) != value
      end
    end

    self.table_name = "mcp_tokens"
    self.filter_attributes += [:digest]

    attribute :scopes, ScopeList.new, default: -> { [] }

    normalizes :machine, with: ->(machine) { machine.strip }
    normalizes :scopes, with: ->(scopes) { scopes.uniq.sort_by { |scope| SCOPES.index(scope) || SCOPES.size } }

    validates :machine, :digest, :expires_at, presence: true
    validate :scopes_known
    validate :scopes_include_read
    validate :lifetime_allowed, on: :create

    scope :live, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }

    ActiveSupport.run_load_hooks(:tailnet_mcp_token, self)

    def self.issue!(machine:, scopes: ["read"], days: 90, **)
      generate_text.tap do |text|
        create!(machine:, scopes:, digest: digest_of(text), expires_at: days.days.from_now, **)
      end
    end

    def self.authenticate(text)
      return unless text.is_a?(String) && text.valid_encoding? && text.match?(pattern)

      live.find_by(digest: digest_of(text))
    end

    def self.generate_text
      "#{TailnetMcp.configuration.token_prefix}_#{SecureRandom.urlsafe_base64(32)}"
    end

    def self.pattern
      /\A#{Regexp.escape(TailnetMcp.configuration.token_prefix)}_[A-Za-z0-9_-]{43}\z/
    end

    # The text is random, so a slow hash would add nothing.
    def self.digest_of(text)
      Digest::SHA256.hexdigest(text)
    end

    def allows?(scope)
      scopes.include?(scope.to_s)
    end

    def revoke!
      update!(revoked_at: Time.current) if revoked_at.nil?
    end

    def serializable_hash(options = nil)
      super.except("digest")
    end

    private

    def scopes_known
      unknown = scopes - SCOPES
      errors.add(:scopes, "are unknown: #{unknown.join(', ')}") if unknown.any?
    end

    def scopes_include_read
      errors.add(:scopes, "must include read") unless allows?(:read)
    end

    def lifetime_allowed
      return if expires_at.nil? || expires_at.between?(Time.current, MAX_DAYS.days.from_now)

      errors.add(:expires_at, "must be within #{MAX_DAYS} days")
    end
  end
end
