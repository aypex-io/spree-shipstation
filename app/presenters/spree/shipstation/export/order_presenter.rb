# frozen_string_literal: true

module Spree
  module Shipstation
    module Export
      ##
      # Shapes a single +Spree::Fulfillment+ (a parcel) into the values
      # ShipStation's export XML expects, keeping data-massaging logic out of the
      # Builder template.
      #
      # Note: ShipStation models one "Order" per parcel, so most order-level
      # fields are derived from +fulfillment.order+ while identifiers come from
      # the fulfillment itself (mirroring the +<OrderNumber>+ = fulfillment.number
      # contract).
      #
      class OrderPresenter
        attr_reader :fulfillment

        ##
        # @param fulfillment [Spree::Fulfillment] the parcel to export
        #
        def initialize(fulfillment)
          @fulfillment = fulfillment
        end

        ##
        # @return [Spree::Order]
        #
        def order
          fulfillment.order
        end

        ##
        # @return [Integer]
        #
        def order_id
          fulfillment.id
        end

        ##
        # The number ShipStation echoes back in the ship notice: the stored number
        # of a parcel created before Spree 6.0, otherwise one derived from its
        # order, such as +R1001-F1+.
        #
        # @return [String]
        #
        def order_number
          fulfillment.number
        end

        ##
        # Always +ready+. The export only offers parcels that can ship now, and
        # merchants' ShipStation status mappings key on this value.
        #
        # @return [String]
        #
        def order_status
          "ready"
        end

        ##
        # @return [String, NilClass]
        #
        def order_date
          format_date(order.completed_at)
        end

        ##
        # @return [String, NilClass]
        #
        def last_modified
          format_date([order.completed_at, fulfillment.updated_at].compact.max)
        end

        ##
        # The name of the delivery method selected for the parcel.
        #
        # @return [String, NilClass]
        #
        def shipping_method_name
          fulfillment.delivery_method&.name
        end

        ##
        # @return [BigDecimal]
        #
        def order_total
          order.total
        end

        ##
        # @return [BigDecimal]
        #
        def tax_total
          order.tax_total
        end

        ##
        # The order's delivery charge, exported as ShipStation's ShippingAmount.
        #
        # @return [BigDecimal]
        #
        def ship_total
          order.delivery_total
        end

        ##
        # Spree order number, exported as ShipStation CustomField1.
        #
        # @return [String]
        #
        def custom_field_1
          order.number
        end

        ##
        # Email truncated to ShipStation's 50-character customer-code limit.
        #
        # @return [String, NilClass]
        #
        def customer_code
          order.email&.slice(0, 50)
        end

        ##
        # @return [Spree::Address, NilClass]
        #
        def bill_address
          order.bill_address
        end

        ##
        # @return [Spree::Address, NilClass]
        #
        def ship_address
          order.ship_address
        end

        ##
        # One presenter per line item that still has a variant, built from the
        # parcel's fulfillment items for that line.
        #
        # @return [Array<Spree::Shipstation::Export::ItemPresenter>]
        #
        def items
          fulfillment.fulfillment_items.group_by(&:line_item).filter_map do |line_item, fulfillment_items|
            next unless line_item.variant

            ItemPresenter.new(line_item, fulfillment_items)
          end
        end

        private

        def format_date(time)
          time&.strftime(ExportHelper::DATE_FORMAT)
        end
      end
    end
  end
end
