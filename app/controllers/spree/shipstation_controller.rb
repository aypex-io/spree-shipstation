# frozen_string_literal: true

module Spree
  ##
  # HTTP endpoints ShipStation polls for ready parcels and posts ship notices to.
  #
  # Every request is answered for one ShipStation integration, and so for one
  # store. The bare +/shipstation+ path uses the default store's integration;
  # +/shipstation/:integration_id+ uses the integration with that prefixed id.
  # Requests are authenticated with HTTP Basic against the integration's own
  # credentials, after the integration is found: with no active integration the
  # answer is 404, whoever asks.
  #
  # This is an +ActionController::Base+ rather than an API controller because
  # the export is a Builder template, which +ActionController::API+ renders as
  # an empty body.
  #
  class ShipstationController < ActionController::Base
    include Spree::Core::ControllerHelpers::Store
    include Pagy::Method

    PER_PAGE = 50
    private_constant :PER_PAGE

    # Forgery protection is the default for this controller, so an action added
    # later is protected until it says otherwise. ShipStation's two actions opt
    # out: HTTP Basic is their authentication and there is no session to forge.
    protect_from_forgery with: :exception
    skip_forgery_protection only: %i[export shipnotify]

    before_action :find_integration
    before_action :authenticate_shipstation

    ##
    # XML export of the store's ready parcels for ShipStation to pull.
    #
    # @return [void]
    #
    def export
      query = Shipstation::ExportQuery.new(
        store: @integration.store,
        from: date_param(:start_date),
        to: date_param(:end_date)
      )
      @pagy, @fulfillments = pagy(query.call, limit: PER_PAGE)

      respond_to do |format|
        format.xml { render layout: false }
      end
    end

    ##
    # Applies a ship notice from ShipStation and fulfils the parcel. The notice
    # travels in the query string; the XML body ShipStation also sends is not read.
    #
    # @return [void]
    #
    def shipnotify
      Shipstation::ShipmentNotice.from_payload(notice_params, store: @integration.store).apply
      head :ok
    rescue Shipstation::Error => e
      Rails.logger.error("ShipStation Notification Error: #{e.message}")
      render plain: e.message, status: :bad_request
    end

    private

    # Only the notice's own fields. Sliced first, so the integration id, the
    # format and ShipStation's other query params are never "unpermitted", which
    # would raise in a host app that treats them so.
    def notice_params
      params.slice(:order_number, :tracking_number, :carrier)
        .permit(:order_number, :tracking_number, :carrier).to_h
    end

    # Finds the active integration this request is for and makes its store the
    # current one. Anything else is a 404, before the caller is asked who they are.
    def find_integration
      @integration = resolve_integration
      return head :not_found unless @integration

      Spree::Current.store = @integration.store
    end

    def resolve_integration
      if params[:integration_id].present?
        Spree::Integrations::Shipstation.active.find_by_prefix_id(params[:integration_id])
      else
        current_store.integrations.active.find_by(type: Spree::Integrations::Shipstation.sti_name)
      end
    end

    # ShipStation sends dates as +MM/DD/YYYY HH:MM+ in UTC. One it cannot read
    # is dropped, which widens the window rather than failing the pull.
    def date_param(name)
      return if params[name].blank?

      Time.strptime("#{params[name]} UTC", "%m/%d/%Y %H:%M %Z")
    rescue ArgumentError
      nil
    end

    def authenticate_shipstation
      authenticate_or_request_with_http_basic do |username, password|
        # Credentials the integration does not hold would match anything blank.
        next false if @integration.preferred_username.blank? || @integration.preferred_password.blank?

        # A non-short-circuiting & so both fields are always compared, and the
        # time taken does not reveal whether the username matched.
        ActiveSupport::SecurityUtils.secure_compare(username.to_s, @integration.preferred_username.to_s) &
          ActiveSupport::SecurityUtils.secure_compare(password.to_s, @integration.preferred_password.to_s)
      end
    end
  end
end
