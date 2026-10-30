# frozen_string_literal: true

RSpec.describe(Spree::Shipstation::ShipmentNotice) do
  let(:store) { create(:store) }

  # A placed order, paid in full, whose only parcel is unfulfilled. Pass factory
  # attributes to turn it into any other kind of order.
  def paid_order(store: self.store, **attributes)
    create(:order_ready_to_ship, store: store, **attributes)
  end

  def parcel_of(order)
    order.fulfillments.first
  end

  # Nothing has been paid, but the total is above zero.
  def unpaid_order
    paid_order(with_payment: false, payment_state: "none")
  end

  # A card was authorized but nothing captured. The payment is created, then the
  # order's statuses are recomputed from it, instead of being written. Pass a
  # +response_code+ the bogus gateway does not recognise and its capture declines.
  def authorized_order(response_code: nil)
    unpaid_order.tap do |order|
      attributes = {order: order, amount: order.total, status: "pending"}
      attributes[:response_code] = response_code if response_code
      create(:payment, **attributes)
      order.update_statuses!
    end
  end

  # Mixed tender: part captured at checkout and the rest authorized, so Spree
  # derives "partially_paid". The captured part is written to payment_total too,
  # as the factory does for a paid order, since payment events are off in tests.
  def partially_paid_order
    unpaid_order.tap do |order|
      create(:payment, order: order, amount: 5, status: "completed")
      create(:payment, order: order, amount: order.total - 5, status: "pending")
      order.update_column(:payment_total, 5)
      order.update_statuses!
    end
  end

  # Ships the parcel through Spree itself, the way a merchant would.
  def fulfill(parcel, tracking:)
    Spree.fulfillment_fulfill_workflow.call(fulfillment: parcel, tracking: tracking)
  end

  def notice(number, tracking: "1Z999AA10123456784", carrier: nil, order_id: nil, store: self.store)
    described_class.from_payload(
      {order_number: number, tracking_number: tracking, carrier: carrier, order_id: order_id},
      store: store
    )
  end

  # Moves a line out of a parcel into a new parcel of its own, the way the
  # dashboard splits one, and returns the new parcel. Spree destroys a parcel
  # that is left with no items.
  def move_line(line, out_of:)
    Spree.fulfillment_create_workflow.call(
      order: out_of.order,
      stock_location: out_of.stock_location,
      items: [{line_item: line, quantity: line.quantity}],
      source_fulfillment: out_of
    ).value
  end

  # The number a parcel derives now, read afresh rather than from an order
  # whose parcels are cached.
  def current_number(parcel)
    Spree::Fulfillment.find(parcel.id).number
  end

  # Spree sends no email itself. A dispatch publishes "fulfillment.fulfilled",
  # carrying a notify_customer flag, and the shipped email is sent by whatever
  # subscribes to it. The block's subscriber is synchronous, so the events are
  # all in by the time the block returns.
  def fulfilled_events
    events = []
    listener = ->(event) { events << event }
    Spree::Events.subscribe("fulfillment.fulfilled", listener)
    yield
    events
  ensure
    Spree::Events.unsubscribe("fulfillment.fulfilled", listener)
  end

  describe ".from_payload" do
    it("reads the order number, tracking number and carrier") do
      built = described_class.from_payload(
        {order_number: "R1-F1", tracking_number: "T1", carrier: "UPS"},
        store: store
      )

      expect(built).to have_attributes(shipment_number: "R1-F1", shipment_tracking: "T1", shipment_carrier: "UPS")
    end

    it("reads ShipStation's OrderID when it is given") do
      built = described_class.from_payload({order_number: "R1-F1", tracking_number: "T1", order_id: 42}, store: store)
      expect(built.shipment_id).to eq(42)
    end

    it("leaves the OrderID empty when it is not given") do
      built = described_class.from_payload({order_number: "R1-F1", tracking_number: "T1"}, store: store)
      expect(built.shipment_id).to be_nil
    end
  end

  describe "#apply" do
    context "when resolving the parcel" do
      it("finds a parcel by its derived number") do
        order = paid_order
        expect(notice("#{order.number}-F1").apply).to eq(parcel_of(order))
      end

      it("finds a parcel from before Spree 6 by the number stored on it") do
        order = paid_order
        # No model API writes the legacy number: the column is frozen data.
        parcel_of(order).update_column(:number, "H12345678901")
        expect(notice("H12345678901").apply).to eq(parcel_of(order))
      end

      it("finds the second parcel of an order whose own number ends in -F9") do
        order = paid_order(number: "SHOP-F9")
        second = create(:fulfillment, order: order, tracking: nil)
        expect(notice("SHOP-F9-F2").apply).to eq(second)
      end

      it("does not find a parcel that is in another store") do
        other_order = paid_order(store: create(:store))
        expect { notice(parcel_of(other_order).number).apply }
          .to raise_error(Spree::Shipstation::ShipmentNotFoundError)
      end

      it("does not find a position the order has no parcel for") do
        order = paid_order
        expect { notice("#{order.number}-F2").apply }
          .to raise_error(Spree::Shipstation::ShipmentNotFoundError)
      end

      # New fulfillments store no number, so a lookup on nil would match them all.
      it("does not find a parcel when the order number is missing") do
        paid_order
        expect { notice(nil).apply }
          .to raise_error(Spree::Shipstation::ShipmentNotFoundError)
      end

      it("does not find a parcel when the order number is empty") do
        paid_order
        expect { notice("").apply }
          .to raise_error(Spree::Shipstation::ShipmentNotFoundError)
      end

      it("does not fulfill any parcel when the order number is missing") do
        order = paid_order
        begin
          notice(nil).apply
        rescue Spree::Shipstation::ShipmentNotFoundError
          nil
        end
        expect(parcel_of(order).reload).to be_unfulfilled
      end

      it("names the number it could not find") do
        expect { notice("DOES-NOT-EXIST").apply }
          .to raise_error(Spree::Shipstation::ShipmentNotFoundError, "Could not find shipment with number DOES-NOT-EXIST")
      end
    end

    # Spree 6.1 drops the column. A test cannot drop it, so the model reports
    # it gone, which is what the guard reads.
    context "when Spree has dropped the stored number column" do
      before do
        columns = Spree::Fulfillment.column_names - ["number"]
        allow(Spree::Fulfillment).to receive(:column_names).and_return(columns)
      end

      def queries_during
        statements = []
        collect = ->(*, payload) { statements << payload[:sql] }
        ActiveSupport::Notifications.subscribed(collect, "sql.active_record") { yield }
        statements
      end

      it("does not look the number up in the column") do
        order = paid_order
        statements = queries_during { notice("#{order.number}-F1").apply }
        expect(statements.grep(/"spree_fulfillments"\."number"/)).to be_empty
      end

      it("still finds a parcel by its derived number") do
        order = paid_order
        expect(notice("#{order.number}-F1").apply).to eq(parcel_of(order))
      end
    end

    context "when the notice carries ShipStation's OrderID" do
      it("finds the parcel the OrderID names") do
        order = paid_order
        expect(notice("#{order.number}-F1", order_id: parcel_of(order).id).apply).to eq(parcel_of(order))
      end

      it("finds a parcel from before Spree 6 by its stored number and OrderID") do
        order = paid_order
        parcel_of(order).update_column(:number, "H12345678901")
        expect(notice("H12345678901", order_id: parcel_of(order).id).apply).to eq(parcel_of(order))
      end

      it("trusts the OrderID when no parcel derives the number any more") do
        order = paid_order
        expect(notice("#{order.number}-F5", order_id: parcel_of(order).id).apply).to eq(parcel_of(order))
      end

      it("does not find a parcel when the number names no order") do
        order = paid_order
        expect { notice("DOES-NOT-EXIST", order_id: parcel_of(order).id).apply }
          .to raise_error(Spree::Shipstation::ShipmentNotFoundError, "Could not find shipment with number DOES-NOT-EXIST")
      end

      it("does not find a parcel whose OrderID is in another store") do
        order = paid_order
        other_parcel = parcel_of(paid_order(store: create(:store)))
        expect { notice(parcel_of(order).number, order_id: other_parcel.id).apply }
          .to raise_error(Spree::Shipstation::ShipmentNotFoundError)
      end

      it("refuses an OrderID that belongs to another of the store's orders") do
        number = parcel_of(paid_order).number
        other_parcel = parcel_of(paid_order)
        expect { notice(number, order_id: other_parcel.id).apply }
          .to raise_error(Spree::Shipstation::ShipmentMismatchError, "Shipment #{number} does not match order id #{other_parcel.id}")
      end

      it("does not fulfil the other order's parcel") do
        number = parcel_of(paid_order).number
        other_parcel = parcel_of(paid_order)
        begin
          notice(number, order_id: other_parcel.id).apply
        rescue Spree::Shipstation::ShipmentMismatchError
          nil
        end
        expect(other_parcel.reload).to be_unfulfilled
      end
    end

    # ShipStation imported two parcels, one line each. Then the first parcel's
    # only line was moved into a new parcel, so Spree destroyed the first and
    # every parcel after it moved up a place: the second now derives the first's
    # old number, and the new parcel the second's.
    context "when Spree has dissolved a parcel ShipStation imported" do
      let(:order) { paid_order(line_items_count: 2) }
      let!(:first) { parcel_of(order) }
      let!(:second) { move_line(order.line_items.second, out_of: first) }
      let!(:imported_numbers) { [current_number(first), current_number(second)] }
      let!(:replacement) { move_line(order.line_items.first, out_of: first) }

      def apply_dissolved_notice
        notice(imported_numbers.first, order_id: first.id).apply
      rescue Spree::Shipstation::ShipmentNotFoundError
        nil
      end

      it("renumbers the parcels after it") do
        expect([current_number(second), current_number(replacement)]).to eq(imported_numbers)
      end

      it("fulfils the parcel the OrderID names") do
        expect(notice(imported_numbers.second, order_id: second.id).apply).to eq(second)
      end

      it("leaves the parcel that now derives that number unfulfilled") do
        notice(imported_numbers.second, order_id: second.id).apply
        expect(replacement.reload).to be_unfulfilled
      end

      it("refuses the dissolved parcel's notice") do
        expect { notice(imported_numbers.first, order_id: first.id).apply }
          .to raise_error(Spree::Shipstation::ShipmentNotFoundError, "Could not find shipment with number #{imported_numbers.first}")
      end

      it("fulfils nothing for the dissolved parcel's notice") do
        apply_dissolved_notice
        expect(order.fulfillments.reload.map(&:status)).to eq(%w[unfulfilled unfulfilled])
      end
    end

    context "when the parcel is paid and unfulfilled" do
      it("fulfills the parcel") do
        order = paid_order
        notice(parcel_of(order).number).apply
        expect(parcel_of(order).reload).to be_fulfilled
      end

      it("records the tracking number") do
        order = paid_order
        notice(parcel_of(order).number, tracking: "1Z1231234").apply
        expect(parcel_of(order).reload.tracking).to eq("1Z1231234")
      end

      it("returns the fulfilled parcel") do
        order = paid_order
        expect(notice(parcel_of(order).number).apply).to be_fulfilled
      end

      it("publishes one fulfilled event, which is what sends the shipped email") do
        order = paid_order
        events = fulfilled_events { notice(parcel_of(order).number).apply }
        expect(events.size).to eq(1)
      end

      it("asks for the customer to be notified") do
        order = paid_order
        events = fulfilled_events { notice(parcel_of(order).number).apply }
        expect(events.first.metadata).to include("notify_customer" => true)
      end
    end

    context "when the tracking number is blank" do
      it("raises a MissingTrackingNumberError") do
        order = paid_order
        expect { notice(parcel_of(order).number, tracking: "").apply }
          .to raise_error(Spree::Shipstation::MissingTrackingNumberError, "Tracking number is required")
      end
    end

    context "when the parcel is canceled" do
      it("raises a FulfillmentCanceledError naming the parcel") do
        order = paid_order
        Spree.fulfillment_cancel_workflow.call(fulfillment: parcel_of(order))
        number = parcel_of(order).number
        expect { notice(number).apply }
          .to raise_error(Spree::Shipstation::FulfillmentCanceledError, "Shipment #{number} is canceled")
      end
    end

    context "when the order is not paid" do
      it("raises a FulfillmentRefusedError with Spree's reason") do
        order = unpaid_order
        expect { notice(parcel_of(order).number).apply }
          .to raise_error(Spree::Shipstation::FulfillmentRefusedError, "This order is not paid for yet")
      end

      it("leaves the parcel unfulfilled") do
        order = unpaid_order
        begin
          notice(parcel_of(order).number).apply
        rescue Spree::Shipstation::FulfillmentRefusedError
          nil
        end
        expect(parcel_of(order).reload).to be_unfulfilled
      end
    end

    context "when an item is backordered" do
      it("raises a FulfillmentRefusedError with Spree's reason") do
        order = paid_order
        parcel_of(order).fulfillment_items.each { |item| item.update!(status: "backordered") }
        expect { notice(parcel_of(order).number).apply }
          .to raise_error(Spree::Shipstation::FulfillmentRefusedError, I18n.t("spree.fulfillments.errors.backordered_units"))
      end
    end

    context "when the parcel is already fulfilled" do
      let(:order) { paid_order }
      let(:number) { parcel_of(order).number }

      before { fulfill(parcel_of(order), tracking: "A1") }

      it("corrects the tracking number") do
        notice(number, tracking: "B2").apply
        expect(parcel_of(order).reload.tracking).to eq("B2")
      end

      it("leaves the parcel fulfilled") do
        notice(number, tracking: "B2").apply
        expect(parcel_of(order).reload).to be_fulfilled
      end

      it("does not publish a second fulfilled event") do
        events = fulfilled_events { notice(number, tracking: "B2").apply }
        expect(events).to be_empty
      end

      it("accepts a repeat of the same notice") do
        notice(number, tracking: "A1").apply
        expect(parcel_of(order).reload.tracking).to eq("A1")
      end

      it("records the carrier of the new label") do
        notice(number, tracking: "B2", carrier: "FedEx").apply
        expect(parcel_of(order).reload.primary_delivery.carrier).to eq("fedex")
      end

      it("refuses a number the parcel already carries on another delivery") do
        Spree.delivery_create_service.call(owner: parcel_of(order), tracking_number: "B2")
        expect { notice(number, tracking: "B2").apply }
          .to raise_error(Spree::Shipstation::FulfillmentRefusedError, "Tracking number has already been taken")
      end
    end

    # "shipped" is a 5.x status, left on a parcel until Spree's upgrade task
    # renames it "fulfilled". No model API writes it any more, so it is written
    # to the column, as the upgrade finds it.
    context "when the parcel still carries the 5.x shipped status" do
      let(:order) { paid_order }
      let(:number) { parcel_of(order).number }

      before { parcel_of(order).update_column(:status, "shipped") }

      it("records the tracking number") do
        notice(number, tracking: "B2").apply
        expect(parcel_of(order).reload.tracking).to eq("B2")
      end

      it("does not publish a fulfilled event") do
        events = fulfilled_events { notice(number, tracking: "B2").apply }
        expect(events).to be_empty
      end

      it("leaves the status for Spree's upgrade task") do
        notice(number, tracking: "B2").apply
        expect(parcel_of(order).reload.status).to eq("shipped")
      end
    end

    context "when the parcel is already delivered" do
      it("corrects the tracking number") do
        order = paid_order
        fulfill(parcel_of(order), tracking: "A1")
        Spree.fulfillment_mark_delivered_workflow.call(fulfillment: parcel_of(order))
        notice(parcel_of(order).number, tracking: "B2").apply
        expect(parcel_of(order).reload.tracking).to eq("B2")
      end
    end

    context "when ShipStation names a carrier" do
      it("records a known carrier on the delivery") do
        order = paid_order
        notice(parcel_of(order).number, tracking: "TRACK1", carrier: "UPS").apply
        expect(parcel_of(order).reload.primary_delivery.carrier).to eq("ups")
      end

      it("matches a carrier whose name has spaces and capitals") do
        order = paid_order
        notice(parcel_of(order).number, tracking: "TRACK1", carrier: "Royal Mail").apply
        expect(parcel_of(order).reload.primary_delivery.carrier).to eq("royal_mail")
      end

      it("ignores a carrier Spree does not know") do
        order = paid_order
        notice(parcel_of(order).number, tracking: "TRACK1", carrier: "Acme Freight").apply
        expect(parcel_of(order).reload.primary_delivery.carrier).to be_nil
      end

      it("still fulfills the parcel when the carrier is unknown") do
        order = paid_order
        notice(parcel_of(order).number, tracking: "TRACK1", carrier: "Acme Freight").apply
        expect(parcel_of(order).reload).to be_fulfilled
      end
    end

    context "when the store captures on dispatch" do
      before { store.update!(preferred_capture_method: "on_dispatch") }

      it("captures the authorized payment") do
        order = authorized_order
        notice(parcel_of(order).number).apply
        expect(order.payments.first.reload).to be_completed
      end

      it("fulfils a parcel paid partly at checkout and partly on dispatch") do
        order = partially_paid_order
        notice(parcel_of(order).number).apply
        expect(parcel_of(order).reload).to be_fulfilled
      end

      context "when the gateway declines the capture" do
        let(:order) { authorized_order(response_code: "DECLINED") }

        def apply_declined_notice
          notice(parcel_of(order).number, tracking: "NEW-TRACKING").apply
        rescue Spree::Shipstation::PaymentError
          nil
        end

        it("raises a PaymentError with the gateway's reason") do
          expect { notice(parcel_of(order).number).apply }
            .to raise_error(Spree::Shipstation::PaymentError, "Could not capture payment: Bogus Gateway: Forced failure")
        end

        it("leaves the parcel unfulfilled") do
          apply_declined_notice
          expect(parcel_of(order).reload).to be_unfulfilled
        end

        # The decline rolls back everything Spree wrote under the order lock,
        # the payment's failed state included, so a retry captures afresh.
        it("leaves the payment pending for the retry") do
          apply_declined_notice
          expect(order.payments.first.reload).to be_pending
        end

        it("does not keep the tracking Spree wrote before the capture failed") do
          before_notice = parcel_of(order).tracking
          apply_declined_notice
          expect(parcel_of(order).reload.tracking).to eq(before_notice)
        end
      end
    end
  end
end
