# frozen_string_literal: true

module Spree
  module Shipstation
    ##
    # Selects the parcels ShipStation should pull: the store's fulfillments that
    # Spree will let ship right now.
    #
    # Spree 6 keeps no "ready" status. A fulfillment is +unfulfilled+ until
    # someone hands it over, and whether it can go out is decided when it is
    # fulfilled. This query asks the same questions ahead of time, so ShipStation
    # is not offered parcels that Spree would refuse at the ship notice. A parcel
    # is exported when all of these hold:
    #
    # * it is one of the store's fulfillments and is still +unfulfilled+;
    # * its order is placed, which leaves out drafts and canceled orders;
    # * its order is paid: +paid+, +overcharged+ or +partially_refunded+, or it
    #   owes nothing (+total = 0+, whose payment status stays +none+), or it is
    #   +authorized+ on a store that captures on dispatch or manually (a payment
    #   method that overrides the store's setting is not consulted);
    # * none of its items is backordered;
    # * its selected delivery method is not a pickup or a pickup point.
    #
    # @example
    #   Spree::Shipstation::ExportQuery.new(store: store, from: 1.day.ago).call
    #
    class ExportQuery
      PAID_STATUSES = %w[paid overcharged partially_refunded].freeze
      private_constant :PAID_STATUSES

      PRELOADS = {
        order: [:bill_address, :ship_address, :fulfillments],
        fulfillment_items: {
          line_item: {
            variant: [{product: :primary_media}, :primary_media, {option_values: :option_type}]
          }
        }
      }.freeze
      private_constant :PRELOADS

      ##
      # @param store [Spree::Store] the store whose fulfillments are exported
      # @param from [Time, NilClass] start of the date window
      # @param to [Time, NilClass] end of the date window
      #
      def initialize(store:, from: nil, to: nil)
        @store = store
        @from = from
        @to = to
      end

      ##
      # The exportable parcels, oldest update first, with everything the export
      # presenters read already loaded.
      #
      # A parcel falls in the window when its own +updated_at+ or its order's does.
      # With neither +from+ nor +to+ there is no window, and with only one of them
      # the window is open-ended.
      #
      # @return [ActiveRecord::Relation<Spree::Fulfillment>]
      #
      def call
        within_window(shippable)
          .reorder(updated_at: :asc, id: :asc)
          .preload(PRELOADS)
      end

      private

      attr_reader :store, :from, :to

      def shippable
        store.fulfillments
          .unfulfilled
          .merge(Spree::Order.placed_orders)
          .merge(paid_orders)
          .where.not(id: backordered)
          .where.not(id: picked_up)
      end

      # A free order's payment status stays +none+, but Spree ships it.
      def paid_orders
        Spree::Order.where(payment_status: paid_statuses).or(Spree::Order.where(total: 0))
      end

      # An authorized order can ship when the store charges it at dispatch or
      # leaves it to staff. On a store that captures at checkout, authorized money
      # is not yet paid.
      def paid_statuses
        store.capture_at_checkout? ? PAID_STATUSES : PAID_STATUSES + ["authorized"]
      end

      # The +fulfillment_id IS NOT NULL+ guards matter: a single NULL in a +NOT IN+
      # list makes the comparison unknown for every row, which would export nothing.
      def backordered
        Spree::FulfillmentItem.backordered.where.not(fulfillment_id: nil).select(:fulfillment_id)
      end

      # Only the delivery method the customer chose counts. A parcel may carry a
      # pickup rate among the options it was offered. Methods are read with
      # deleted ones, since orders outlive the method they were placed with.
      def picked_up
        pickups = Spree::DeliveryMethod.with_deleted.with_provider(:pickup?)
          .or(Spree::DeliveryMethod.with_deleted.with_provider(:pickup_point?))

        Spree::DeliveryRate
          .where(selected: true, delivery_method_id: pickups.select(:id))
          .where.not(fulfillment_id: nil)
          .select(:fulfillment_id)
      end

      def within_window(scope)
        return scope if from.nil? && to.nil?

        window = from..to
        scope.where(updated_at: window).or(scope.where(Spree::Order.table_name => {updated_at: window}))
      end
    end
  end
end
