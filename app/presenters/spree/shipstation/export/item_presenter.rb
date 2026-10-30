# frozen_string_literal: true

module Spree
  module Shipstation
    module Export
      ##
      # Shapes a parcel's line item (a line item plus its fulfillment items) into
      # the values ShipStation's export XML expects for an +<Item>+.
      #
      class ItemPresenter
        attr_reader :line_item, :fulfillment_items

        ##
        # @param line_item [Spree::LineItem] the line item
        # @param fulfillment_items [Array<Spree::FulfillmentItem>] the parcel's
        #   fulfillment items for that line
        #
        def initialize(line_item, fulfillment_items)
          @line_item = line_item
          @fulfillment_items = fulfillment_items
        end

        ##
        # @return [Spree::Variant]
        #
        def variant
          @variant ||= line_item.variant
        end

        ##
        # @return [String]
        #
        def sku
          variant.sku
        end

        ##
        # Product name plus variant options, dropping blanks.
        #
        # @return [String]
        #
        def name
          [variant.product.name, variant.options_text].reject(&:blank?).join(" ")
        end

        ##
        # The +Spree::Media+ to advertise, or +nil+: the variant's primary media,
        # else its product's. URL generation stays in the view because it depends
        # on Rails route/URL helpers.
        #
        # @return [Spree::Media, NilClass]
        #
        def image
          variant.thumbnail
        end

        ##
        # @return [Spree::Shipstation::Export::Weight]
        #
        def weight
          Weight.from_variant(variant)
        end

        ##
        # The number of items to ship, summed across the line's fulfillment items.
        #
        # Spree stores a quantity on each +Spree::FulfillmentItem+ rather than one
        # row per item, so counting rows under-reports any line ordered more
        # than once.
        #
        # @return [Integer]
        #
        def quantity
          fulfillment_items.sum(&:quantity)
        end

        ##
        # @return [BigDecimal]
        #
        def unit_price
          line_item.price
        end

        ##
        # The variant's options as pairs of the option type's label and the
        # option value's name, which is how ShipStation lists them.
        #
        # @return [Array<Array(String, String)>]
        #
        def option_values
          variant.option_values.map { |value| [value.option_type.label, value.name] }
        end
      end
    end
  end
end
