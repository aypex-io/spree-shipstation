# frozen_string_literal: true

module Spree
  module Shipstation
    module Export
      ##
      # Shapes a shipment line item (a line item plus its inventory units) into the
      # values ShipStation's export XML expects for an +<Item>+.
      #
      class ItemPresenter
        attr_reader :line_item, :units

        ##
        # @param line_item [Spree::LineItem] the line item
        # @param units [Array<Spree::InventoryUnit>] inventory units for that line
        #
        def initialize(line_item, units)
          @line_item = line_item
          @units = units
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
        # The +Spree::Image+ to advertise, or +nil+. URL generation stays in the
        # view because it depends on Rails route/URL helpers.
        #
        # @return [Spree::Image, NilClass]
        #
        def image
          variant.images.first || variant.product.master.images.first
        end

        ##
        # @return [Spree::Shipstation::Export::Weight]
        #
        def weight
          Weight.from_variant(variant)
        end

        ##
        # The number of items to ship, summed across the line's inventory units.
        #
        # Spree stores a quantity on each +Spree::InventoryUnit+ rather than one
        # row per item, so counting rows under-reports any line ordered more
        # than once.
        #
        # @return [Integer]
        #
        def quantity
          units.sum(&:quantity)
        end

        ##
        # @return [BigDecimal]
        #
        def unit_price
          line_item.price
        end

        ##
        # @return [ActiveRecord::Relation, Array]
        #
        def option_values
          variant.option_values
        end
      end
    end
  end
end
