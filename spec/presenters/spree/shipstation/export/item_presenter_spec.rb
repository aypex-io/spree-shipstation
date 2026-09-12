# frozen_string_literal: true

require "spec_helper"

RSpec.describe(Spree::Shipstation::Export::ItemPresenter) do
  let!(:store) { create(:store, default: true) }
  let(:order) { create(:order_ready_to_ship, store: store) }
  let(:shipment) { order.shipments.first }
  let(:line_item) { shipment.inventory_units.first.line_item }
  let(:units) { shipment.inventory_units.select { |unit| unit.line_item == line_item } }

  subject(:presenter) { described_class.new(line_item, units) }

  it("exposes the variant sku") { expect(presenter.sku).to eq(line_item.variant.sku) }

  it("exposes the unit price") { expect(presenter.unit_price).to eq(line_item.price) }

  it("builds a Weight value object from the variant") do
    expect(presenter.weight).to eq(Spree::Shipstation::Export::Weight.from_variant(line_item.variant))
  end

  describe "#quantity" do
    # An order placed with quantity N gets ONE inventory unit carrying
    # quantity: N (Spree::Stock::InventoryUnitBuilder), not N unit rows.
    def rebuild_units_for(quantities)
      shipment.inventory_units.destroy_all
      quantities.each do |quantity|
        shipment.inventory_units.create!(
          order_id: shipment.order_id,
          variant_id: line_item.variant_id,
          line_item_id: line_item.id,
          quantity: quantity
        )
      end
      shipment.inventory_units.reload.to_a
    end

    it("reports a single unit's quantity") do
      expect(described_class.new(line_item, rebuild_units_for([1])).quantity).to eq(1)
    end

    it("reports the quantity carried by one inventory unit") do
      line_item.update_columns(quantity: 2)

      expect(described_class.new(line_item, rebuild_units_for([2])).quantity).to eq(2)
    end

    it("sums the quantity when a line is split across several inventory units") do
      line_item.update_columns(quantity: 3)

      expect(described_class.new(line_item, rebuild_units_for([2, 1])).quantity).to eq(3)
    end
  end

  describe "#name" do
    it("joins the product name with the variant options text, dropping blanks") do
      allow(line_item.variant).to receive(:options_text).and_return("")

      expect(presenter.name).to eq(line_item.variant.product.name)
    end

    it("includes the options text when present") do
      allow(line_item.variant).to receive(:options_text).and_return("Size: L")

      expect(presenter.name).to eq("#{line_item.variant.product.name} Size: L")
    end
  end

  describe "#image" do
    it("prefers a variant image") do
      variant_image = instance_double(Spree::Image)
      allow(line_item.variant).to receive(:images).and_return([variant_image])

      expect(presenter.image).to eq(variant_image)
    end

    it("falls back to the product master image when the variant has none") do
      master_image = instance_double(Spree::Image)
      allow(line_item.variant).to receive(:images).and_return([])
      allow(line_item.variant.product.master).to receive(:images).and_return([master_image])

      expect(presenter.image).to eq(master_image)
    end
  end
end
