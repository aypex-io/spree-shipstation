# frozen_string_literal: true

RSpec.describe(Spree::Shipstation::ExportQuery) do
  let(:store) { create(:store) }

  # A placed order, paid in full, whose only parcel is unfulfilled and sits in
  # stock. The parcel is shipped by a standard (non-pickup) delivery method.
  # Pass factory attributes to turn it into any other kind of order.
  def paid_order(store: self.store, **attributes)
    create(:order_ready_to_ship, store: store, **attributes).tap do |order|
      parcel_of(order).add_delivery_method(create(:delivery_method), true)
    end
  end

  def parcel_of(order)
    order.fulfillments.first
  end

  # Nothing has been paid, but the total is above zero.
  def unpaid_order
    paid_order(with_payment: false, payment_state: "none")
  end

  # An order that owes nothing: its payment status stays "none", yet Spree
  # still ships it.
  def free_order
    paid_order(with_payment: false, payment_state: "none", line_items_price: 0, shipment_cost: 0)
  end

  # A card was authorized but nothing captured. Spree derives the status from
  # the payments, so the payment is created and the statuses are recomputed
  # instead of being written.
  def authorized_order
    unpaid_order.tap do |order|
      create(:payment, order: order, amount: order.total, status: "pending")
      order.update_statuses!
    end
  end

  # A completed payment with part of it refunded, recomputed the same way.
  def partially_refunded_order
    paid_order.tap do |order|
      create(:refund, amount: 5, payment: order.payments.first)
      order.update_statuses!
    end
  end

  def backorder(parcel)
    parcel.fulfillment_items.each { |item| item.update!(status: "backordered") }
  end

  def exported(store: self.store, from: nil, to: nil)
    described_class.new(store: store, from: from, to: to).call
  end

  # +updated_at+ is the only column no factory or model API can set in
  # isolation: saving a parcel touches its order, and the other way round.
  def stamp(record, time)
    record.update_columns(updated_at: time)
  end

  def count_queries
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end

  describe "#call" do
    it("returns a relation of fulfillments") do
      expect(exported).to be_a(ActiveRecord::Relation)
    end

    context "when the order is placed, paid and unfulfilled" do
      it("includes the parcel") do
        order = paid_order
        expect(exported).to eq([parcel_of(order)])
      end
    end

    context "when the order is unpaid" do
      it("excludes the parcel") do
        order = unpaid_order
        expect(exported).not_to include(parcel_of(order))
      end
    end

    context "when an item is backordered" do
      it("excludes the parcel") do
        order = paid_order
        backorder(parcel_of(order))
        expect(exported).not_to include(parcel_of(order))
      end
    end

    context "when a backordered item belongs to no parcel" do
      it("still includes a shippable parcel") do
        order = paid_order
        create(:fulfillment_item, :without_assoc, line_item: order.line_items.first, status: "backordered")
        expect(exported).to eq([parcel_of(order)])
      end
    end

    context "when the order is free" do
      it("includes the parcel") do
        order = free_order
        expect(exported).to eq([parcel_of(order)])
      end
    end

    context "when the order is only authorized" do
      context "when the store captures on dispatch" do
        it("includes the parcel") do
          store.update!(preferred_capture_method: "on_dispatch")
          order = authorized_order
          expect(exported).to eq([parcel_of(order)])
        end
      end

      context "when the store leaves capture to staff" do
        it("includes the parcel") do
          store.update!(preferred_capture_method: "manual")
          order = authorized_order
          expect(exported).to eq([parcel_of(order)])
        end
      end

      context "when the store captures at checkout" do
        it("excludes the parcel") do
          store.update!(preferred_capture_method: "checkout")
          order = authorized_order
          expect(exported).not_to include(parcel_of(order))
        end
      end
    end

    context "when the order is partially refunded" do
      it("includes the parcel") do
        order = partially_refunded_order
        expect(exported).to eq([parcel_of(order)])
      end
    end

    context "when the parcel is already fulfilled" do
      it("excludes the parcel") do
        order = paid_order
        Spree.fulfillment_fulfill_workflow.call(fulfillment: parcel_of(order), tracking: "1Z999AA10123456784")
        expect(exported).not_to include(parcel_of(order))
      end
    end

    context "when the order was canceled through Spree" do
      it("excludes the parcel") do
        order = paid_order
        Spree.order_cancel_workflow.call(order: order)
        expect(exported).not_to include(parcel_of(order))
      end
    end

    context "when the order is canceled but its parcel still reads unfulfilled" do
      it("excludes the parcel") do
        order = paid_order
        order.update!(status: "canceled")
        expect(exported).not_to include(parcel_of(order))
      end
    end

    context "when the order is a draft" do
      it("excludes the parcel") do
        order = paid_order
        order.update!(status: "draft")
        expect(exported).not_to include(parcel_of(order))
      end
    end

    context "when the parcel is a store pickup" do
      it("excludes the parcel") do
        order = paid_order
        parcel_of(order).delivery_rates.destroy_all
        parcel_of(order).add_delivery_method(create(:pickup_delivery_method), true)
        expect(exported).not_to include(parcel_of(order))
      end
    end

    context "when the parcel goes to a pickup point" do
      it("excludes the parcel") do
        order = paid_order
        parcel_of(order).delivery_rates.destroy_all
        parcel_of(order).add_delivery_method(create(:pickup_point_delivery_method), true)
        expect(exported).not_to include(parcel_of(order))
      end
    end

    context "when the pickup method has since been deleted" do
      it("excludes the parcel") do
        order = paid_order
        pickup = create(:pickup_delivery_method)
        parcel_of(order).delivery_rates.destroy_all
        parcel_of(order).add_delivery_method(pickup, true)
        pickup.destroy
        expect(exported).not_to include(parcel_of(order))
      end
    end

    context "when pickup was only offered and a standard method was chosen" do
      it("includes the parcel") do
        order = paid_order
        parcel_of(order).add_delivery_method(create(:pickup_delivery_method), false)
        expect(exported).to eq([parcel_of(order)])
      end
    end

    context "when the order has no delivery method at all" do
      it("includes the parcel") do
        order = paid_order
        parcel_of(order).delivery_rates.destroy_all
        expect(exported).to eq([parcel_of(order)])
      end
    end

    context "when the order belongs to another store" do
      it("excludes the parcel") do
        order = paid_order(store: create(:store))
        expect(exported).not_to include(parcel_of(order))
      end
    end

    context "when a backordered parcel sits beside a shippable one" do
      let!(:order) { paid_order }
      let!(:backordered_parcel) { parcel_of(order) }
      let!(:shippable_parcel) { create(:fulfillment, order: order, tracking: nil) }

      before { backorder(backordered_parcel) }

      it("exports only the shippable parcel") do
        expect(exported).to eq([shippable_parcel])
      end

      it("numbers it by its place among the order's parcels") do
        expect(exported.first.number).to eq("#{order.number}-F2")
      end
    end
  end

  describe "the date window" do
    let(:from) { 3.days.ago }
    let(:to) { 1.day.ago }
    let(:inside) { 2.days.ago }
    let(:outside) { 10.days.ago }

    it("matches a parcel updated inside the window") do
      order = paid_order
      stamp(order, outside)
      stamp(parcel_of(order), inside)
      expect(exported(from: from, to: to)).to eq([parcel_of(order)])
    end

    it("matches a parcel whose order was updated inside the window") do
      order = paid_order
      stamp(parcel_of(order), outside)
      stamp(order, inside)
      expect(exported(from: from, to: to)).to eq([parcel_of(order)])
    end

    it("excludes a parcel when neither it nor its order was updated inside the window") do
      order = paid_order
      stamp(parcel_of(order), outside)
      stamp(order, outside)
      expect(exported(from: from, to: to)).to be_empty
    end

    it("lists the parcel once when both fall inside the window") do
      order = paid_order
      stamp(parcel_of(order), inside)
      stamp(order, inside)
      expect(exported(from: from, to: to).to_a.size).to eq(1)
    end

    it("applies no filter when neither bound is given") do
      order = paid_order
      stamp(parcel_of(order), outside)
      stamp(order, outside)
      expect(exported).to eq([parcel_of(order)])
    end

    it("treats a lone start as open-ended") do
      recent = paid_order
      old = paid_order
      [recent, old].each { |order| stamp(order, outside) }
      stamp(parcel_of(recent), inside)
      stamp(parcel_of(old), outside)
      expect(exported(from: from)).to eq([parcel_of(recent)])
    end

    it("treats a lone end as open-ended") do
      early = paid_order
      late = paid_order
      [early, late].each { |order| stamp(order, 1.hour.ago) }
      stamp(parcel_of(early), inside)
      stamp(parcel_of(late), 1.hour.ago)
      expect(exported(to: to)).to eq([parcel_of(early)])
    end

    it("still applies the other filters inside the window") do
      order = unpaid_order
      stamp(parcel_of(order), inside)
      stamp(order, inside)
      expect(exported(from: from, to: to)).to be_empty
    end
  end

  describe "the order of the result" do
    it("sorts parcels by their updated_at, oldest first") do
      newer = paid_order
      older = paid_order
      stamp(parcel_of(newer), 1.hour.ago)
      stamp(parcel_of(older), 2.hours.ago)
      expect(exported.to_a).to eq([parcel_of(older), parcel_of(newer)])
    end

    # Rows with equal timestamps would otherwise come back in an arbitrary order,
    # which shifts parcels between ShipStation's pages.
    it("breaks ties by id") do
      sorts = exported.order_values.map { |sort| [sort.expr.name.to_s, sort.direction] }
      expect(sorts).to eq([["updated_at", :asc], ["id", :asc]])
    end
  end

  describe "the preloads" do
    let(:variant) { create(:variant) }

    # Walks what the export presenters read for each parcel.
    def read_everything(parcels)
      parcels.each do |parcel|
        parcel.number
        parcel.order.bill_address
        parcel.order.ship_address
        parcel.fulfillment_items.each do |item|
          product_variant = item.line_item.variant
          product_variant.product.name
          product_variant.options_text
          product_variant.option_values.map { |value| value.option_type.label }
          product_variant.thumbnail&.still_image&.blob
        end
      end
    end

    it("loads the order, addresses, items, variants and options up front") do
      paid_order(variants: [variant])
      parcels = exported.to_a
      expect(count_queries { read_everything(parcels) }).to eq(0)
    end

    it("loads the variant's own media up front") do
      paid_order(variants: [variant])
      create(:media, viewable: variant)
      parcels = exported.to_a
      expect(count_queries { read_everything(parcels) }).to eq(0)
    end

    it("loads the product's media up front when the variant has none") do
      paid_order(variants: [variant])
      create(:media, viewable: variant.product)
      parcels = exported.to_a
      expect(count_queries { read_everything(parcels) }).to eq(0)
    end

    it("loads the selected delivery method up front") do
      paid_order(variants: [variant])
      parcels = exported.to_a
      expect(count_queries { parcels.each { |parcel| parcel.delivery_method.name } }).to eq(0)
    end

    it("loads the order's other parcels so each number costs no query") do
      order = paid_order
      create(:fulfillment, order: order, tracking: nil)
      parcels = exported.to_a
      expect(count_queries { parcels.each(&:number) }).to eq(0)
    end
  end
end
