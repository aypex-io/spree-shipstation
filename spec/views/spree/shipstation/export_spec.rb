# frozen_string_literal: true

require "spec_helper"

RSpec.describe("spree/shipstation/export.xml.builder", type: :view) do
  let!(:store) { create(:store, default: true) }
  let(:option_type) { create(:option_type, label: "Size") }
  let(:option_value) { create(:option_value, option_type: option_type, name: "small", label: "S") }
  let(:variant) { create(:variant, option_values: [option_value]) }
  let(:order) { create(:order_ready_to_ship, store: store, variants: [variant]) }
  let(:fulfillment) { order.fulfillments.first }
  let(:document) { Nokogiri::XML(rendered) }

  def text_at(path)
    document.at_xpath(path)&.text
  end

  def render_export
    fulfillment.add_delivery_method(create(:delivery_method), true)
    assign(:fulfillments, Spree::Shipstation::ExportQuery.new(store: store).call)
    assign(:pagy, Pagy::Offset.new(count: 1, page: 1, limit: 50))
    render template: "spree/shipstation/export", formats: [:xml]
  end

  context "with a placed, paid fulfillment" do
    before { render_export }

    it("passes ShipStation's XML schema") do
      expect(rendered).to pass_validation("spec/fixtures/shipstation_xml_schema.xsd")
    end

    it("reports the page count") do
      expect(document.at_xpath("/Orders/@pages").value).to eq("1")
    end

    it("exports the fulfillment's id as the OrderID") do
      expect(text_at("//Order/OrderID")).to eq(fulfillment.id.to_s)
    end

    it("exports the fulfillment's number as the OrderNumber") do
      expect(text_at("//Order/OrderNumber")).to eq(fulfillment.number)
    end

    it("exports the status as ready") do
      expect(text_at("//Order/OrderStatus")).to eq("ready")
    end

    it("exports the selected delivery method as the ShippingMethod") do
      expect(text_at("//Order/ShippingMethod")).to eq(fulfillment.delivery_method.name)
    end

    it("exports the order's delivery total as the ShippingAmount") do
      expect(text_at("//Order/ShippingAmount")).to eq(order.delivery_total.to_s)
    end

    it("exports the ship-to name from the address's full name") do
      expect(text_at("//ShipTo/Name")).to eq(order.ship_address.full_name)
    end

    it("exports the ship-to postal code") do
      expect(text_at("//ShipTo/PostalCode")).to eq(order.ship_address.postal_code)
    end

    it("exports the ship-to country code") do
      expect(text_at("//ShipTo/Country")).to eq(order.ship_address.country_code)
    end

    it("exports the ship-to state code") do
      expect(text_at("//ShipTo/State")).to eq(order.ship_address.state_code)
    end

    it("exports the item's option type label as the option name") do
      expect(text_at("//Item/Options/Option/Name")).to eq("Size")
    end

    it("exports the option value's name as the option value") do
      expect(text_at("//Item/Options/Option/Value")).to eq("small")
    end

    it("exports the quantity of the fulfillment's items") do
      expect(text_at("//Item/Quantity")).to eq(fulfillment.fulfillment_items.sum(&:quantity).to_s)
    end

    it("omits the ImageUrl when the variant has no media") do
      expect(document.at_xpath("//Item/ImageUrl")).to be_nil
    end
  end

  context "when the variant has an image" do
    before do
      create(:media, viewable: variant)
      render_export
    end

    it("exports a URL for the image") do
      expect(text_at("//Item/ImageUrl")).to match(%r{\A/rails/active_storage/})
    end

    it("still passes ShipStation's XML schema") do
      expect(rendered).to pass_validation("spec/fixtures/shipstation_xml_schema.xsd")
    end
  end

  context "when the product has an image and the variant has none" do
    before do
      create(:media, viewable: variant.product)
      render_export
    end

    it("exports a URL for the product's image") do
      expect(text_at("//Item/ImageUrl")).to match(%r{\A/rails/active_storage/})
    end
  end

  context "when the variant's thumbnail is an external video" do
    before do
      create(:external_video_media, viewable: variant)
      render_export
    end

    it("omits the ImageUrl") do
      expect(document.at_xpath("//Item/ImageUrl")).to be_nil
    end
  end
end
