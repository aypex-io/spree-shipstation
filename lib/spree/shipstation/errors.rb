# frozen_string_literal: true

module Spree
  module Shipstation
    ##
    # Base error for ShipStation integration failures returned as HTTP 400.
    #
    class Error < StandardError; end

    ##
    # Raised when the shipnotify payload names a shipment that does not exist.
    #
    class ShipmentNotFoundError < Error
      ##
      # @param shipment_number [String] the shipment number from the payload
      #
      def initialize(shipment_number, *args)
        super("Could not find shipment with number #{shipment_number}", *args)
      end
    end

    ##
    # Raised when the ship notice's +OrderID+ names a fulfillment of a different
    # order from the one its order number names.
    #
    class ShipmentMismatchError < Error
      ##
      # @param shipment_number [String] the order number from the notice
      # @param shipment_id [Integer] the +OrderID+ from the notice
      #
      def initialize(shipment_number, shipment_id, *args)
        super("Shipment #{shipment_number} does not match order id #{shipment_id}", *args)
      end
    end

    ##
    # Raised when the shipnotify payload names a shipment Spree has canceled.
    #
    class FulfillmentCanceledError < Error
      ##
      # @param shipment_number [String] the number of the canceled shipment
      #
      def initialize(shipment_number, *args)
        super("Shipment #{shipment_number} is canceled", *args)
      end
    end

    ##
    # Raised when Spree refuses to fulfil the shipment, for instance because the
    # order is not paid or holds backordered items. The message is Spree's own.
    #
    class FulfillmentRefusedError < Error; end

    ##
    # Raised when a payment cannot be captured during shipnotify.
    #
    class PaymentError < Error
      ##
      # @param message [String] why the capture failed, as the gateway reported it
      #
      def initialize(message, *args)
        super("Could not capture payment: #{message}", *args)
      end
    end

    ##
    # Raised when shipnotify is called without a tracking number.
    #
    class MissingTrackingNumberError < Error
      def initialize(*args)
        super("Tracking number is required", *args)
      end
    end
  end
end
