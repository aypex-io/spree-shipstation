# frozen_string_literal: true

require "spec_helper"
require "builder"

RSpec.describe(Spree::Shipstation::ExportHelper) do
  describe "address rendering" do
    let(:xml) { Builder::XmlMarkup.new }

    # Addresses are built, not saved: the helper only reads them.
    def address(**attributes)
      build(
        :address,
        first_name: "Jane",
        last_name: "Doe",
        company: "Acme",
        address1: "1 Main St",
        address2: "Apt 2",
        city: "Springfield",
        state_code: "IL",
        state_name: nil,
        postal_code: "12345",
        country_code: "US",
        phone: "555-1234",
        **attributes
      )
    end

    describe ".ship_address" do
      it("emits nothing when the address is missing") do
        described_class.ship_address(xml, nil)

        expect(xml.target!).to eq("")
      end

      it("emits the ship-to name from the full name") do
        described_class.ship_address(xml, address)

        expect(xml.target!).to include("<Name>Jane Doe</Name>")
      end

      it("emits street-level fields") do
        described_class.ship_address(xml, address)

        expect(xml.target!).to include("<Address1>1 Main St</Address1>")
      end

      it("emits the state code, postal code and country code") do
        described_class.ship_address(xml, address(state_code: "CA", postal_code: "90210", country_code: "US"))

        expect(xml.target!).to include("<State>CA</State><PostalCode>90210</PostalCode><Country>US</Country>")
      end

      it("reads the codes from the address, so no country or state record is needed") do
        described_class.ship_address(xml, address(state_code: "ZZ", country_code: "ZZ"))

        expect(xml.target!).to include("<State>ZZ</State>", "<Country>ZZ</Country>")
      end

      it("falls back to the state name when the state code is blank") do
        described_class.ship_address(xml, address(state_code: "", state_name: "Illinois"))

        expect(xml.target!).to include("<State>Illinois</State>")
      end

      it("falls back to the state name when the state code is missing") do
        described_class.ship_address(xml, address(state_code: nil, state_name: "Illinois"))

        expect(xml.target!).to include("<State>Illinois</State>")
      end
    end

    describe ".bill_address" do
      it("emits nothing when the address is missing") do
        described_class.bill_address(xml, nil)

        expect(xml.target!).to eq("")
      end

      it("emits a BillTo name") do
        described_class.bill_address(xml, address)

        expect(xml.target!).to include("<Name>Jane Doe</Name>")
      end

      it("omits street-level fields") do
        described_class.bill_address(xml, address)

        expect(xml.target!).not_to include("Address1")
      end
    end
  end
end
