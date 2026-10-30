# frozen_string_literal: true

module Spree
  module Shipstation
    ##
    # Applies a ShipStation shipnotify payload to a Spree fulfillment.
    #
    # The payload's order number is the +OrderNumber+ the export sent, which is a
    # fulfillment's number, and its order id, when ShipStation sends one, is the
    # +OrderID+ the export sent, which is the fulfillment's id. The notice
    # resolves the fulfillment within the store:
    #
    # * without an order id, by its number: the number stored on a fulfillment
    #   from before Spree 6, else the number Spree derives from its order;
    # * with one, by that id, which is authoritative. A derived number is the
    #   parcel's position in its order, so when Spree destroys an earlier parcel
    #   (every item moved out of it) the later ones take new numbers, and an old
    #   number may now name a sibling. The number still has to name the
    #   fulfillment's order; a fulfillment that no longer exists is not found,
    #   never matched on its number instead.
    #
    # Then, under the order's row lock (which serializes ShipStation's retries):
    #
    # * a fulfillment that is already fulfilled or delivered only has its
    #   tracking recorded, so a retry or a re-label does not fulfil it or
    #   publish the event again;
    # * a canceled one is refused;
    # * any other goes through Spree's fulfil workflow, which checks the order is
    #   paid and in stock, records the tracking and carrier, captures payments
    #   that capture on dispatch, and publishes +fulfillment.fulfilled+ with
    #   +notify_customer+ set. The host app's subscriber to that event decides
    #   whether, and how, to tell the customer.
    #
    # @example
    #   Spree::Shipstation::ShipmentNotice.from_payload(
    #     {order_number: "R1001-F1", order_id: 1001, tracking_number: "1Z999AA10123456784", carrier: "UPS"},
    #     store: store
    #   ).apply
    #
    class ShipmentNotice
      # Splits a derived fulfillment number into its order's number and its
      # position. The order part is greedy, so an order number that itself ends
      # in "-F9" still parses. Only the order is used: the parcel is matched on
      # Spree's own derived number rather than on the position.
      DERIVED_NUMBER = /\A(?<order>.+)-F(?<position>\d+)\z/
      private_constant :DERIVED_NUMBER

      attr_reader :shipment_number, :shipment_id, :shipment_tracking, :shipment_carrier, :store

      class << self
        ##
        # Builds a notice from the shipnotify webhook params.
        #
        # ShipStation's webhook param is named +order_number+ but its value is
        # the fulfillment number — it mirrors the +<OrderNumber>+ field from the
        # export XML. Likewise +order_id+ is the +<OrderID>+ field, the
        # fulfillment's id, which ShipStation sends in the notice's XML body.
        #
        # @param params [Hash] webhook params: +:order_number+, +:tracking_number+,
        #   and optionally +:carrier+ and +:order_id+
        # @param store [Spree::Store] store that owns the fulfillment
        # @return [Spree::Shipstation::ShipmentNotice]
        #
        def from_payload(params, store:)
          new(
            shipment_number: params[:order_number],
            shipment_id: params[:order_id],
            shipment_tracking: params[:tracking_number],
            shipment_carrier: params[:carrier],
            store: store
          )
        end
      end

      ##
      # @param shipment_number [String] Spree fulfillment number
      # @param shipment_tracking [String] carrier tracking number
      # @param store [Spree::Store] store that owns the fulfillment
      # @param shipment_carrier [String, NilClass] ShipStation's carrier name
      # @param shipment_id [Integer, NilClass] ShipStation's +OrderID+, the
      #   fulfillment's id; when given, it decides which fulfillment is meant
      #
      def initialize(shipment_number:, shipment_tracking:, store:, shipment_carrier: nil, shipment_id: nil)
        @shipment_number = shipment_number
        @shipment_id = shipment_id
        @shipment_tracking = shipment_tracking
        @shipment_carrier = shipment_carrier
        @store = store
      end

      ##
      # Records the tracking number and fulfils the parcel, unless it already is.
      #
      # A gateway decline rolls back everything Spree wrote under the order lock,
      # so the parcel stays unfulfilled, its payment stays pending and the retry
      # starts from the same place.
      #
      # @return [Spree::Fulfillment] the updated fulfillment
      # @raise [Spree::Shipstation::ShipmentNotFoundError] when the fulfillment is missing
      # @raise [Spree::Shipstation::ShipmentMismatchError] when the order id names
      #   a fulfillment of another order than the number does
      # @raise [Spree::Shipstation::MissingTrackingNumberError] when tracking is blank
      # @raise [Spree::Shipstation::FulfillmentCanceledError] when the fulfillment is canceled
      # @raise [Spree::Shipstation::FulfillmentRefusedError] when Spree refuses to fulfil it
      # @raise [Spree::Shipstation::PaymentError] when a payment cannot be captured
      #
      def apply
        fulfillment = find_fulfillment
        raise MissingTrackingNumberError if shipment_tracking.blank?

        fulfillment.order.with_lock do
          # Reloaded under the lock: a retry that waited for it sees what the
          # first request did.
          fulfillment.reload
          apply_to(fulfillment)
        end
      rescue ::Spree::Core::GatewayError => e
        # Rescued outside the lock, as Spree's own fulfil endpoint does. Inside
        # it, the transaction would commit a fulfilled parcel whose capture failed.
        raise PaymentError, e.message
      end

      private

      def find_fulfillment
        # New fulfillments store no number, so looking up a blank one would match
        # every one of them and fulfil an arbitrary parcel.
        raise ShipmentNotFoundError, shipment_number if shipment_number.blank?
        return find_by_shipment_id if shipment_id

        find_by_stored_number || find_by_derived_number || raise(ShipmentNotFoundError, shipment_number)
      end

      # The id is checked against the order the number names, which survives a
      # renumbering even when the parcel's own derived number does not. It never
      # falls back to the number: the parcel the id named may have been destroyed,
      # and its number handed to a sibling.
      def find_by_shipment_id
        order = find_by_stored_number&.order || order_of_derived_number
        raise ShipmentNotFoundError, shipment_number unless order

        fulfillment = store.fulfillments.find_by(id: shipment_id)
        raise ShipmentNotFoundError, shipment_number unless fulfillment
        raise ShipmentMismatchError.new(shipment_number, shipment_id) unless fulfillment.order_id == order.id

        fulfillment
      end

      # Parcels created before Spree 6 keep the number stored on them.
      def find_by_stored_number
        store.fulfillments.find_by(number: shipment_number)
      end

      def find_by_derived_number
        order_of_derived_number&.fulfillments&.detect { |fulfillment| fulfillment.number == shipment_number }
      end

      # The store's order a derived number names, whether or not any of its
      # parcels derives that number now.
      def order_of_derived_number
        match = DERIVED_NUMBER.match(shipment_number.to_s)
        return unless match

        store.orders.find_by(number: match[:order])
      end

      def apply_to(fulfillment)
        if fulfillment.fulfilled_or_delivered?
          record_tracking(fulfillment)
        elsif fulfillment.canceled?
          raise FulfillmentCanceledError, fulfillment.number
        else
          fulfil(fulfillment)
        end
      end

      def record_tracking(fulfillment)
        result = ::Spree.delivery_upsert_primary_service.call(
          fulfillment: fulfillment, tracking: shipment_tracking, carrier: tracking_carrier
        )
        raise FulfillmentRefusedError, result.error.to_s if result.failure?

        fulfillment.reload
      end

      # Never passes +items:+ or +force:+: a partial list would split the parcel
      # and ship a new fulfillment under a different number, and forcing would
      # ship an unpaid or backordered one.
      def fulfil(fulfillment)
        result = ::Spree.fulfillment_fulfill_workflow.call(
          fulfillment: fulfillment,
          tracking: shipment_tracking,
          tracking_carrier: tracking_carrier,
          notify_customer: true
        )
        raise FulfillmentRefusedError, result.error.to_s if result.failure?

        result.value
      end

      # ShipStation's carrier name as a Spree.tracking_carriers key, or nil when
      # Spree has no such carrier, in which case it detects one from the number.
      def tracking_carrier
        key = shipment_carrier.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_|_\z/, "")
        key if ::Spree.tracking_carriers.key?(key)
      end
    end
  end
end
