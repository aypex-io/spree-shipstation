# frozen_string_literal: true

module Spree
  ##
  # HTTP endpoints ShipStation polls for ready shipments and posts ship notices to.
  #
  class ShipstationController < ActionController::Base
    include Pagy::Method

    protect_from_forgery with: :null_session, only: :shipnotify

    before_action :ensure_active_integration
    before_action :authenticate_shipstation

    ##
    # XML export of ready shipments for ShipStation to pull.
    #
    # @return [void]
    #
    def export
      @pagy, @shipments = pagy(
        current_store.shipments
          .exportable
          .between(date_param(:start_date), date_param(:end_date)),
        page: params[:page],
        items: 50
      )

      respond_to do |format|
        format.xml { render layout: false }
      end
    end

    ##
    # Applies a ship notification from ShipStation and marks the shipment shipped.
    #
    # @return [void]
    #
    def shipnotify
      Shipstation::ShipmentNotice.from_payload(params.permit(:order_number, :tracking_number).to_h, store: current_store).apply
      head :ok
    rescue Shipstation::Error => e
      Rails.logger.error("ShipStation Notification Error: #{e.message}")
      render plain: e.message, status: :bad_request
    end

    private

    def ensure_active_integration
      head :not_found unless store_integration("shipstation")&.active?
    end

    def date_param(name)
      return if params[name].blank?

      Time.strptime("#{params[name]} UTC", "%m/%d/%Y %H:%M %Z")
    rescue ArgumentError
      nil
    end

    def authenticate_shipstation
      authenticate_or_request_with_http_basic do |username, password|
        integration = store_integration("shipstation")
        ActiveSupport::SecurityUtils.secure_compare(username.to_s, integration.preferred_username.to_s) &&
          ActiveSupport::SecurityUtils.secure_compare(password.to_s, integration.preferred_password.to_s)
      end
    end
  end
end
