# frozen_string_literal: true

module Spree
  module Integrations
    ##
    # Per-store ShipStation credentials registered with Spree's integration framework.
    #
    class Shipstation < Spree::Integration
      I18N_SCOPE = "spree.admin.integrations.shipstation"

      # Password complexity rules, checked in order. Each key names the
      # translation shown when its pattern does not match.
      PASSWORD_RULES = {
        must_contain_at_least_one_special_character: /[!@#$%^&*(),.?":{}|<>]/,
        must_contain_at_least_one_uppercase_letter: /[A-Z]/,
        must_contain_at_least_one_number: /\d/
      }.freeze

      LOGO_PATH = Spree::Shipstation::Engine.root.join("app/assets/images/integration_icons/shipstation-icon.png")

      preference :username, :string

      validates :preferred_username,
        presence: true,
        length: {minimum: 10, maximum: 30}

      # Restrict to characters that are safe to send in an HTTP Basic Auth header:
      # a-z, A-Z, 0-9, and . _ @ + -
      validates :preferred_username,
        format: {
          with: /\A[a-zA-Z0-9._@+-]+\z/,
          message: ->(_record, _data) { I18n.t("username_chars_error", scope: I18N_SCOPE) }
        },
        allow_blank: true

      preference :password, :password

      validates :preferred_password,
        presence: true,
        length: {minimum: 20, maximum: 60}

      validate :password_complexity

      ##
      # Dashboard group key. Matches the group Spree's own shipping integrations use.
      #
      # @return [String]
      #
      def self.integration_group
        "shipping"
      end

      ##
      # Brand name shown in the dashboard's integrations list.
      #
      # @return [String]
      #
      def self.integration_name
        I18n.t("brand_name", scope: I18N_SCOPE)
      end

      ##
      # The bundled logo as a +data:+ URI, so the dashboard can render it with
      # no asset pipeline and no hosted file. Read once, then memoised.
      #
      # @return [String]
      #
      def self.logo_url
        # Array#pack("m0") is strict Base64 without the base64 gem, which
        # Ruby 3.4 and later no longer ship as a default gem.
        @logo_url ||= "data:image/png;base64,#{[LOGO_PATH.binread].pack("m0")}".freeze
      end

      ##
      # Link to this extension's setup guide, shown on the dashboard's gallery card.
      #
      # @return [String]
      #
      def self.docs_url
        "https://github.com/aypex-io/spree-shipstation#readme"
      end

      private

      # Adds an error for each complexity rule the password fails. Written as a
      # method rather than three +format:+ validations because those patterns
      # are deliberately unanchored ("contains"), which Brakeman flags.
      def password_complexity
        password = preferred_password
        return if password.blank?

        PASSWORD_RULES.each do |message_key, pattern|
          next if pattern.match?(password)

          errors.add(:preferred_password, I18n.t(message_key, scope: I18N_SCOPE))
        end
      end
    end
  end
end
