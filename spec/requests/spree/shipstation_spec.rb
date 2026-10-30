# frozen_string_literal: true

RSpec.describe("ShipStation endpoints", type: :request) do
  let!(:store) { create(:store, default: true) }
  let(:integration) { create(:shipstation_integration, store: store) }

  # Basic auth the way ShipStation sends it.
  def credentials(integration)
    {"HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(
      integration.preferred_username, integration.preferred_password
    )}
  end

  # A placed order, paid in full, whose only parcel is unfulfilled and ready to ship.
  def paid_order(store: self.store, **attributes)
    create(:order_ready_to_ship, store: store, **attributes)
  end

  # Nothing has been paid, but the total is above zero.
  def unpaid_order
    paid_order(with_payment: false, payment_state: "none")
  end

  def parcel_of(order)
    order.fulfillments.first
  end

  def order_numbers
    Nokogiri::XML(response.body).xpath("//Order/OrderNumber").map(&:text)
  end

  # ShipStation puts the notice in the query string and sends an XML body that
  # the endpoint does not read.
  def ship_notice(path, number:, tracking: "1Z999AA10123456784", carrier: "UPS", headers: {})
    query = {order_number: number, tracking_number: tracking, carrier: carrier}.to_query
    post "#{path}?#{query}", params: "<ShipNotice/>", headers: headers.merge("CONTENT_TYPE" => "text/xml")
  end

  def window(from, to)
    {start_date: from.utc.strftime("%m/%d/%Y %H:%M"), end_date: to.utc.strftime("%m/%d/%Y %H:%M")}
  end

  context "when the store has no active integration" do
    it("answers a pull with 404 before asking for credentials") do
      get "/shipstation.xml"
      expect(response).to have_http_status(:not_found)
    end

    it("answers a ship notice with 404 before asking for credentials") do
      post "/shipstation"
      expect(response).to have_http_status(:not_found)
    end

    it("answers a pull for an inactive integration with 404") do
      integration.update!(active: false)
      get "/shipstation.xml", headers: credentials(integration)
      expect(response).to have_http_status(:not_found)
    end

    it("answers a ship notice for an inactive integration with 404") do
      integration.update!(active: false)
      post "/shipstation", headers: credentials(integration)
      expect(response).to have_http_status(:not_found)
    end
  end

  context "with an active integration" do
    before { integration }

    describe "authentication" do
      it("answers a pull without credentials with 401") do
        get "/shipstation.xml"
        expect(response).to have_http_status(:unauthorized)
      end

      it("answers a pull with the wrong username with 401") do
        headers = {"HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(
          "some_wrong_username", integration.preferred_password
        )}
        get "/shipstation.xml", headers: headers
        expect(response).to have_http_status(:unauthorized)
      end

      it("answers a pull with the wrong password with 401") do
        headers = {"HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(
          integration.preferred_username, "not_the_correct-password"
        )}
        get "/shipstation.xml", headers: headers
        expect(response).to have_http_status(:unauthorized)
      end

      it("answers a ship notice with the wrong credentials with 401") do
        ship_notice("/shipstation", number: "R1-F1", headers: {"HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("a", "b")})
        expect(response).to have_http_status(:unauthorized)
      end

      it("leaves the parcel unfulfilled when a ship notice is refused") do
        parcel = parcel_of(paid_order)
        ship_notice("/shipstation", number: parcel.number)
        expect(parcel.reload.status).to eq("unfulfilled")
      end
    end

    describe "GET /shipstation.xml" do
      let!(:paid) { paid_order }
      let!(:unpaid) { unpaid_order }

      it("answers 200") do
        get "/shipstation.xml", headers: credentials(integration)
        expect(response).to have_http_status(:ok)
      end

      it("answers application/xml") do
        get "/shipstation.xml", headers: credentials(integration)
        expect(response.media_type).to eq("application/xml")
      end

      it("passes ShipStation's XML schema") do
        get "/shipstation.xml", headers: credentials(integration)
        expect(response.body).to pass_validation("spec/fixtures/shipstation_xml_schema.xsd")
      end

      it("exports the paid parcel") do
        get "/shipstation.xml", headers: credentials(integration)
        expect(order_numbers).to include(parcel_of(paid).number)
      end

      it("leaves out the unpaid parcel") do
        get "/shipstation.xml", headers: credentials(integration)
        expect(order_numbers).not_to include(parcel_of(unpaid).number)
      end

      it("answers a pull without an extension with 200") do
        get "/shipstation", headers: credentials(integration)
        expect(response).to have_http_status(:ok)
      end

      it("answers a pull without an extension with XML") do
        get "/shipstation", headers: credentials(integration)
        expect(response.media_type).to eq("application/xml")
      end

      it("answers a pull without an extension with the paid parcel") do
        get "/shipstation", headers: credentials(integration)
        expect(order_numbers).to eq([parcel_of(paid).number])
      end
    end

    describe "pagination" do
      # Extra parcels on one paid order: each carries the order's items, so it
      # ships just as a parcel of its own order would.
      before do
        order = paid_order
        50.times { create(:fulfillment, order: order) }
      end

      it("reports two pages for 51 parcels") do
        get "/shipstation.xml", headers: credentials(integration)
        expect(Nokogiri::XML(response.body).at_xpath("/Orders/@pages").value).to eq("2")
      end

      it("puts 50 parcels on the first page") do
        get "/shipstation.xml", headers: credentials(integration)
        expect(order_numbers.size).to eq(50)
      end

      it("puts the last parcel on the second page") do
        get "/shipstation.xml", params: {page: 2}, headers: credentials(integration)
        expect(order_numbers.size).to eq(1)
      end
    end

    describe "page param" do
      let!(:paid) { paid_order }

      it("reads a page that is not a number as the first page") do
        get "/shipstation.xml", params: {page: "abc"}, headers: credentials(integration)
        expect(order_numbers).to eq([parcel_of(paid).number])
      end

      it("answers a page past the last with 200") do
        get "/shipstation.xml", params: {page: 5}, headers: credentials(integration)
        expect(response).to have_http_status(:ok)
      end

      it("lists no parcels on a page past the last") do
        get "/shipstation.xml", params: {page: 5}, headers: credentials(integration)
        expect(order_numbers).to be_empty
      end
    end

    describe "date params" do
      let!(:recent) { paid_order }
      let!(:old) do
        paid_order.tap do |order|
          # +updated_at+ is the only column no model API sets in isolation:
          # saving a parcel touches its order and the other way round.
          order.update_columns(updated_at: 10.days.ago)
          parcel_of(order).update_columns(updated_at: 10.days.ago)
        end
      end

      it("exports a parcel updated inside the window") do
        get "/shipstation.xml", params: window(1.day.ago, 1.day.from_now), headers: credentials(integration)
        expect(order_numbers).to include(parcel_of(recent).number)
      end

      it("leaves out a parcel updated before the window") do
        get "/shipstation.xml", params: window(1.day.ago, 1.day.from_now), headers: credentials(integration)
        expect(order_numbers).not_to include(parcel_of(old).number)
      end

      it("reads an end date that excludes the parcel") do
        get "/shipstation.xml", params: window(30.days.ago, 5.days.ago), headers: credentials(integration)
        expect(order_numbers).to eq([parcel_of(old).number])
      end

      it("ignores an unparseable start date") do
        get "/shipstation.xml", params: {start_date: "yesterday-ish"}, headers: credentials(integration)
        expect(order_numbers).to contain_exactly(parcel_of(recent).number, parcel_of(old).number)
      end

      it("ignores an unparseable end date") do
        get "/shipstation.xml", params: {end_date: "13/45/2026 99:99"}, headers: credentials(integration)
        expect(order_numbers).to contain_exactly(parcel_of(recent).number, parcel_of(old).number)
      end
    end

    describe "POST /shipstation" do
      let(:order) { paid_order }
      let(:parcel) { parcel_of(order) }

      it("answers a ship notice with 200") do
        ship_notice("/shipstation", number: parcel.number, headers: credentials(integration))
        expect(response).to have_http_status(:ok)
      end

      it("fulfils the parcel") do
        ship_notice("/shipstation", number: parcel.number, headers: credentials(integration))
        expect(parcel.reload.status).to eq("fulfilled")
      end

      it("records the tracking number") do
        ship_notice("/shipstation", number: parcel.number, tracking: "1Z0000000000000042", headers: credentials(integration))
        expect(parcel.reload.tracking).to eq("1Z0000000000000042")
      end

      it("answers a ship notice for an unpaid parcel with 400") do
        ship_notice("/shipstation", number: parcel_of(unpaid_order).number, headers: credentials(integration))
        expect(response).to have_http_status(:bad_request)
      end

      it("explains why an unpaid parcel was refused") do
        ship_notice("/shipstation", number: parcel_of(unpaid_order).number, headers: credentials(integration))
        expect(response.body).to eq("This order is not paid for yet")
      end

      it("answers a ship notice for an unknown parcel with 400") do
        ship_notice("/shipstation", number: "NOPE-F1", headers: credentials(integration))
        expect(response.body).to eq("Could not find shipment with number NOPE-F1")
      end

      context "when forgery protection is on" do
        around do |example|
          previous = ActionController::Base.allow_forgery_protection
          ActionController::Base.allow_forgery_protection = true
          example.run
        ensure
          ActionController::Base.allow_forgery_protection = previous
        end

        it("accepts the notice without a CSRF token") do
          ship_notice("/shipstation", number: parcel.number, headers: credentials(integration))
          expect(response).to have_http_status(:ok)
        end
      end
    end

    describe "with several stores" do
      let(:other_store) { create(:store) }
      let(:other_integration) do
        create(
          :shipstation_integration,
          store: other_store,
          preferred_username: "secondstoreuser-4821",
          preferred_password: "Zq9!secondStorePassw0rd-xyz"
        )
      end
      let!(:own_order) { paid_order }
      let!(:other_order) { paid_order(store: other_store) }
      let(:other_path) { "/shipstation/#{other_integration.prefixed_id}" }

      it("exports only the other store's parcels on its integration's URL") do
        get "#{other_path}.xml", headers: credentials(other_integration)
        expect(order_numbers).to eq([parcel_of(other_order).number])
      end

      it("passes ShipStation's XML schema on the integration's URL") do
        get "#{other_path}.xml", headers: credentials(other_integration)
        expect(response.body).to pass_validation("spec/fixtures/shipstation_xml_schema.xsd")
      end

      it("answers the integration's URL without an extension with XML") do
        get other_path, headers: credentials(other_integration)
        expect(response.media_type).to eq("application/xml")
      end

      it("exports only the default store's parcels on the bare URL") do
        other_integration
        get "/shipstation.xml", headers: credentials(integration)
        expect(order_numbers).to eq([parcel_of(own_order).number])
      end

      it("refuses the first store's credentials on the other store's URL") do
        get "#{other_path}.xml", headers: credentials(integration)
        expect(response).to have_http_status(:unauthorized)
      end

      it("refuses the other store's credentials on the bare URL") do
        get "/shipstation.xml", headers: credentials(other_integration)
        expect(response).to have_http_status(:unauthorized)
      end

      it("ships the other store's parcel on its integration's URL") do
        parcel = parcel_of(other_order)
        ship_notice(other_path, number: parcel.number, headers: credentials(other_integration))
        expect(parcel.reload.status).to eq("fulfilled")
      end

      it("does not find another store's parcel on the integration's URL") do
        parcel = parcel_of(own_order)
        ship_notice(other_path, number: parcel.number, headers: credentials(other_integration))
        expect(response).to have_http_status(:bad_request)
      end

      it("leaves another store's parcel unfulfilled") do
        parcel = parcel_of(own_order)
        ship_notice(other_path, number: parcel.number, headers: credentials(other_integration))
        expect(parcel.reload.status).to eq("unfulfilled")
      end

      it("answers an unknown integration id with 404") do
        get "/shipstation/int_nonexistent.xml", headers: credentials(other_integration)
        expect(response).to have_http_status(:not_found)
      end

      it("answers another model's prefixed id with 404") do
        get "/shipstation/#{store.prefixed_id}.xml", headers: credentials(integration)
        expect(response).to have_http_status(:not_found)
      end

      it("answers an inactive integration's URL with 404") do
        other_integration.update!(active: false)
        get "#{other_path}.xml", headers: credentials(other_integration)
        expect(response).to have_http_status(:not_found)
      end

      it("answers a ship notice for an unknown integration id with 404") do
        ship_notice("/shipstation/int_nonexistent", number: "R1-F1", headers: credentials(other_integration))
        expect(response).to have_http_status(:not_found)
      end

      it("answers 404 before asking for credentials on an unknown integration id") do
        get "/shipstation/int_nonexistent.xml"
        expect(response).to have_http_status(:not_found)
      end

      it("does not serve another store's integration on the bare URL") do
        integration.update!(active: false)
        get "/shipstation.xml", headers: credentials(other_integration)
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
