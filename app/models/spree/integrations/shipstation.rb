# frozen_string_literal: true

module Spree
  module Integrations
    ##
    # Per-store ShipStation credentials registered with Spree's integration framework.
    #
    class Shipstation < Spree::Integration
      preference :username, :string

      validates :preferred_username,
        presence: true,
        length: {minimum: 10, maximum: 30}

      # Restrict to characters that are safe to send in an HTTP Basic Auth header:
      # a-z, A-Z, 0-9, and . _ @ + -
      validates :preferred_username,
        format: {
          with: /\A[a-zA-Z0-9._@+-]+\z/,
          message: ->(_record, _data) { I18n.t("spree.admin.integrations.shipstation.username_chars_error") }
        },
        allow_blank: true

      preference :password, :password

      validates :preferred_password,
        presence: true,
        length: {minimum: 20, maximum: 60}

      validates :preferred_password,
        format: {
          with: /[!@#$%^&*(),.?":{}|<>]/,
          message: ->(_record, _data) { I18n.t("spree.admin.integrations.shipstation.must_contain_at_least_one_special_character") }
        },
        allow_blank: true

      validates :preferred_password,
        format: {
          with: /[A-Z]/,
          message: ->(_record, _data) { I18n.t("spree.admin.integrations.shipstation.must_contain_at_least_one_uppercase_letter") }
        },
        allow_blank: true

      validates :preferred_password,
        format: {
          with: /\d/,
          message: ->(_record, _data) { I18n.t("spree.admin.integrations.shipstation.must_contain_at_least_one_number") }
        },
        allow_blank: true

      ##
      # Admin grouping for this integration.
      #
      # @return [String]
      #
      def self.integration_group
        "Shipping"
      end

      ##
      # Path to the logo shown in the admin integrations list.
      #
      # @return [String]
      #
      def self.icon_path
        "integration_icons/shipstation-logo.webp"
      end

      ##
      # Translated brand name shown in the admin integrations list.
      #
      # @return [String]
      #
      def self.integration_name
        I18n.t("spree.admin.integrations.shipstation.brand_name")
      end
    end
  end
end
