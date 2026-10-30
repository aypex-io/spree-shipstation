# frozen_string_literal: true

require "spec_helper"

RSpec.describe(Spree::Shipstation::Export::OrderPresenter) do
  let!(:store) { create(:store, default: true) }
  let(:order) { create(:order_ready_to_ship, store: store) }
  # The factory's parcel already has a standard delivery method selected.
  let(:fulfillment) { order.fulfillments.first }

  subject(:presenter) { described_class.new(fulfillment) }

  describe "identifiers" do
    it("derives the order id from the fulfillment") { expect(presenter.order_id).to eq(fulfillment.id) }

    it("derives the order number from the fulfillment") do
      expect(presenter.order_number).to eq(fulfillment.number)
    end

    it("numbers a new fulfillment after its order") { expect(presenter.order_number).to eq("#{order.number}-F1") }

    it("reports every exported fulfillment as ready") { expect(presenter.order_status).to eq("ready") }
  end

  describe "order-level fields" do
    it("exposes the order total") { expect(presenter.order_total).to eq(order.total) }

    it("exposes the tax total") { expect(presenter.tax_total).to eq(order.tax_total) }

    it("exposes the order's delivery total as the ship total") do
      expect(presenter.ship_total).to eq(order.delivery_total)
    end

    it("exposes the order number as CustomField1") { expect(presenter.custom_field_1).to eq(order.number) }

    it("truncates the customer code to 50 characters") do
      order.update!(email: "#{"a" * 60}@example.com")

      expect(presenter.customer_code.length).to eq(50)
    end
  end

  describe "#shipping_method_name" do
    # Read from the rates rather than through the fulfillment, as the presenter
    # reads it.
    it("names the selected delivery method") do
      selected = Spree::DeliveryRate.find_by!(fulfillment_id: fulfillment.id, selected: true)
      expect(presenter.shipping_method_name).to eq(selected.delivery_method.name)
    end

    it("is nil when the fulfillment has no delivery method") do
      fulfillment.delivery_rates.destroy_all

      expect(presenter.shipping_method_name).to be_nil
    end
  end

  describe "#order_date" do
    it("formats the completed_at timestamp using the shared date format") do
      expect(presenter.order_date)
        .to eq(order.completed_at.strftime(Spree::Shipstation::ExportHelper::DATE_FORMAT))
    end
  end

  describe "#last_modified" do
    it("uses the latest of completed_at and the fulfillment updated_at") do
      latest = [order.completed_at, fulfillment.updated_at].compact.max

      expect(presenter.last_modified).to eq(latest.strftime(Spree::Shipstation::ExportHelper::DATE_FORMAT))
    end
  end

  describe "#items" do
    it("returns an ItemPresenter per line item with a variant") do
      expect(presenter.items).to all(be_a(Spree::Shipstation::Export::ItemPresenter))
    end

    it("presents the fulfillment's only line item once") do
      expect(presenter.items.size).to eq(1)
    end

    it("groups a line item's fulfillment items under one presenter") do
      line_item = fulfillment.fulfillment_items.first.line_item
      fulfillment.fulfillment_items.create!(order: order, variant: line_item.variant, line_item: line_item)

      expect(presenter.items.size).to eq(1)
    end

    context "when the order has several line items" do
      let(:order) { create(:order_ready_to_ship, store: store, line_items_count: 2) }

      it("presents one item per line item") do
        expect(presenter.items.size).to eq(2)
      end
    end

    it("skips line items without a variant") do
      fulfillment.fulfillment_items.first.line_item.update_columns(variant_id: nil)

      expect(described_class.new(Spree::Fulfillment.find(fulfillment.id)).items).to be_empty
    end
  end
end
