# frozen_string_literal: true

require "spec_helper"

RSpec.describe(Spree::Shipstation::Export::ItemPresenter) do
  let!(:store) { create(:store, default: true) }
  let(:option_type) { create(:option_type, label: "Size") }
  let(:option_value) { create(:option_value, option_type: option_type, name: "small", label: "S") }
  let(:variant) { create(:variant, option_values: [option_value]) }
  let(:order) { create(:order_ready_to_ship, store: store, variants: [variant]) }
  let(:fulfillment) { order.fulfillments.first }
  let(:fulfillment_items) { fulfillment.fulfillment_items.to_a }
  let(:line_item) { fulfillment_items.first.line_item }

  subject(:presenter) { described_class.new(line_item, fulfillment_items) }

  it("exposes the variant sku") { expect(presenter.sku).to eq(variant.sku) }

  it("exposes the unit price") { expect(presenter.unit_price).to eq(line_item.price) }

  it("builds a Weight value object from the variant") do
    expect(presenter.weight).to eq(Spree::Shipstation::Export::Weight.from_variant(variant))
  end

  describe "#quantity" do
    # A line ordered N times is stored as ONE fulfillment item carrying
    # quantity N, not as N rows, and a line may also be split across several.
    def items_of(quantities)
      line = line_item
      fulfillment.fulfillment_items.destroy_all
      quantities.map do |quantity|
        fulfillment.fulfillment_items.create!(order: order, variant: line.variant, line_item: line, quantity: quantity)
      end
    end

    it("reports a single item's quantity") do
      expect(described_class.new(line_item, items_of([1])).quantity).to eq(1)
    end

    it("reports the quantity carried by one fulfillment item") do
      expect(described_class.new(line_item, items_of([3])).quantity).to eq(3)
    end

    it("sums the quantity when a line is split across several fulfillment items") do
      expect(described_class.new(line_item, items_of([2, 1])).quantity).to eq(3)
    end
  end

  describe "#name" do
    it("joins the product name with the variant options text") do
      expect(presenter.name).to eq("#{variant.product.name} Size: S")
    end

    context "when the variant has no options" do
      let(:variant) { create(:variant, option_values: []) }

      it("is the product name alone") do
        expect(presenter.name).to eq(variant.product.name)
      end
    end
  end

  describe "#option_values" do
    it("pairs each option type's label with the value's name") do
      expect(presenter.option_values).to eq([%w[Size small]])
    end

    context "when the variant has no options" do
      let(:variant) { create(:variant, option_values: []) }

      it("is empty") { expect(presenter.option_values).to be_empty }
    end
  end

  describe "#image" do
    it("is nil when neither the variant nor its product has media") do
      expect(presenter.image).to be_nil
    end

    it("is the variant's thumbnail") do
      create(:media, viewable: variant)

      expect(presenter.image).to eq(variant.reload.thumbnail)
    end

    it("is a Spree::Media") do
      create(:media, viewable: variant)

      expect(presenter.image).to be_a(Spree::Media)
    end

    it("falls back to the product's media when the variant has none") do
      product_media = create(:media, viewable: variant.product)

      expect(presenter.image).to eq(product_media)
    end

    it("prefers the variant's own media over the product's") do
      create(:media, viewable: variant.product)
      variant_media = create(:media, viewable: variant)

      expect(presenter.image).to eq(variant_media)
    end
  end
end
