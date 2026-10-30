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

    it("explains a missing special character through I18n") do
      integration.preferred_password = "ValidPassword1xxxxxxx"
      integration.valid?

      expect(integration.errors[:preferred_password]).to eq(["must contain at least one special character"])
    end

    it("explains a missing uppercase letter through I18n") do
      integration.preferred_password = "validpassword1@xxxxxx"
      integration.valid?

      expect(integration.errors[:preferred_password]).to eq(["must contain at least one uppercase letter"])
    end

    it("explains a missing number through I18n") do
      integration.preferred_password = "ValidPassword@xxxxxxx"
      integration.valid?

      expect(integration.errors[:preferred_password]).to eq(["must contain at least one number"])
    end

    it("reports each failed complexity rule") do
      integration.preferred_password = "x" * 20
      integration.valid?

      expect(integration.errors[:preferred_password]).to eq([
        "must contain at least one special character",
        "must contain at least one uppercase letter",
        "must contain at least one number"
      ])
    end

    it("explains disallowed username characters through I18n") do
      integration.preferred_username = "invalid username!"
      integration.valid?

      expect(integration.errors[:preferred_username]).to eq(["can only contain letters, numbers, and . _ @ + -"])
    end
  end

  describe "class metadata" do
    it("groups with Spree's shipping integrations") do
      expect(described_class.integration_group).to eq("shipping")
    end

    it("exposes a brand integration name") do
      expect(described_class.integration_name).to eq("ShipStation")
    end

    it("shows a logo the dashboard can render without the asset pipeline") do
      expect(described_class.logo_url).to start_with("data:image/webp;base64,")
    end

    it("embeds the bundled logo file") do
      encoded = described_class.logo_url.delete_prefix("data:image/webp;base64,")

      expect(encoded.unpack1("m0")).to eq(File.binread(described_class::LOGO_PATH))
    end

    it("links to its docs") do
      expect(described_class.docs_url).to eq("https://github.com/aypex-io/spree-shipstation#readme")
    end

    # Spree 6 resolves the gallery description through human_description, which
    # reads spree.integrations.<api_type>.description before the class default.
    it("describes itself") do
      expect(described_class.human_description).to eq(I18n.t("spree.integrations.shipstation.description"))
    end

    it("is registered with Spree") do
      expect(Spree.integrations.map(&:to_s)).to include("Spree::Integrations::Shipstation")
    end

    it("lists itself in the dashboard's type discovery") do
      entry = Spree::Integration.discovery_entries.find { |e| e[:type] == "shipstation" }

      expect(entry).to include(
        name: "ShipStation",
        group: "shipping",
        description: I18n.t("spree.integrations.shipstation.description"),
        docs_url: "https://github.com/aypex-io/spree-shipstation#readme"
      )
    end
  end
end
