# frozen_string_literal: true

require "spec_helper"

RSpec.describe(Spree::Integrations::Shipstation) do
  let!(:store) { create(:store, default: true) }

  subject(:integration) { build(:shipstation_integration) }

  it("is valid with the factory defaults") { expect(integration).to be_valid }

  describe "username validations" do
    it("is invalid without a username") do
      integration.preferred_username = nil

      expect(integration).not_to be_valid
    end

    it("is invalid when shorter than 10 characters") do
      integration.preferred_username = "a" * 9

      expect(integration).not_to be_valid
    end

    it("is valid at the minimum length of 10 characters") do
      integration.preferred_username = "a" * 10

      expect(integration).to be_valid
    end

    it("is invalid when longer than 30 characters") do
      integration.preferred_username = "a" * 31

      expect(integration).not_to be_valid
    end

    it("is valid at the maximum length of 30 characters") do
      integration.preferred_username = "a" * 30

      expect(integration).to be_valid
    end

    it("allows the documented safe characters") do
      integration.preferred_username = "user.name_01@host+tag-x"

      expect(integration).to be_valid
    end

    it("is invalid with characters outside the safe set") do
      integration.preferred_username = "invalid username!"

      expect(integration).not_to be_valid
    end
  end

  describe "password validations" do
    # A baseline password that satisfies every complexity rule and the length bounds.
    let(:valid_password) { "ValidPassword1@xxxxxx" }

    it("is invalid without a password") do
      integration.preferred_password = nil

      expect(integration).not_to be_valid
    end

    it("is invalid when shorter than 20 characters") do
      integration.preferred_password = "Short1@pass"

      expect(integration).not_to be_valid
    end

    it("is invalid when longer than 60 characters") do
      integration.preferred_password = "A1@#{"a" * 60}"

      expect(integration).not_to be_valid
    end

    it("is valid when all complexity rules and length bounds are met") do
      integration.preferred_password = valid_password

      expect(integration).to be_valid
    end

    it("is invalid without a special character") do
      integration.preferred_password = "ValidPassword1xxxxxxx"

      expect(integration).not_to be_valid
    end

    it("is invalid without an uppercase letter") do
      integration.preferred_password = "validpassword1@xxxxxx"

      expect(integration).not_to be_valid
    end

    it("is invalid without a number") do
      integration.preferred_password = "ValidPassword@xxxxxxx"

      expect(integration).not_to be_valid
    end
  end

  describe "class metadata" do
    it("belongs to the Shipping integration group") do
      expect(described_class.integration_group).to eq("Shipping")
    end

    it("exposes a brand integration name") do
      expect(described_class.integration_name).to eq(I18n.t("spree.admin.integrations.shipstation.brand_name"))
    end

    it("points at the ShipStation logo asset") do
      expect(described_class.icon_path).to eq("integration_icons/shipstation-logo.webp")
    end
  end
end
