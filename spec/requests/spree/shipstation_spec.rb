# frozen_string_literal: true

RSpec.describe("ShipStation endpoints", type: :request) do
  let!(:store) { create(:store, default: true) }
  let(:integration) { create(:shipstation_integration, store: store) }

  # Basic auth the way ShipStation sends it. Pass a username or password to send
  # something other than what the integration holds.
  def credentials(integration, username: integration.preferred_username, password: integration.preferred_password)
    {"HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(username, password)}
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

  # ShipStation puts the notice in the query string and sends it again as an XML
  # body, of which the endpoint reads only the OrderID.
  def ship_notice(path, number:, tracking: "1Z999AA10123456784", carrier: "UPS", body: "<ShipNotice/>", headers: {}, **extra)
    query = {order_number: number, tracking_number: tracking, carrier: carrier, **extra}.to_query
    post "#{path}?#{query}", params: body, headers: headers.merge("CONTENT_TYPE" => "text/xml")
  end

  # A ship notice body as ShipStation sends it, with generic values.
  def ship_notice_xml(number:, order_id:)
    <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <ShipNotice>
        <OrderNumber>#{number}</OrderNumber>
        <OrderID>#{order_id}</OrderID>
        <CustomerCode>customer@example.com</CustomerCode>
        <LabelCreateDate>10/30/2026 09:15</LabelCreateDate>
        <ShipDate>10/30/2026</ShipDate>
        <Carrier>UPS</Carrier>
        <Service>UPS Ground</Service>
        <TrackingNumber>1Z999AA10123456784</TrackingNumber>
        <ShippingCost>4.95</ShippingCost>
        <Recipient>
          <Name>Jane Doe</Name>
          <Address1>1 Example Street</Address1>
          <City>Springfield</City>
          <State>IL</State>
          <PostalCode>62701</PostalCode>
          <Country>US</Country>
        </Recipient>
        <Items>
          <Item>
            <SKU>SKU-1</SKU>
            <Name>Example product</Name>
            <Quantity>1</Quantity>
          </Item>
        </Items>
      </ShipNotice>
    XML
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
        get "/shipstation.xml", headers: credentials(integration, username: "some_wrong_username")
        expect(response).to have_http_status(:unauthorized)
      end

      it("answers a pull with the wrong password with 401") do
        get "/shipstation.xml", headers: credentials(integration, password: "not_the_correct-password")
        expect(response).to have_http_status(:unauthorized)
      end

      it("answers blank credentials with 401 when the stored password is blank") do
        # Validations make a blank password unreachable through normal saves, so
        # it is written past them.
        integration.preferred_password = ""
        integration.save!(validate: false)
        get "/shipstation.xml", headers: credentials(integration)
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
        expect(response).to have_http_status(:bad_request)
      end

      it("names the parcel it could not find") do
        ship_notice("/shipstation", number: "NOPE-F1", headers: credentials(integration))
        expect(response.body).to eq("Could not find shipment with number NOPE-F1")
      end

      context "when the body carries an OrderID" do
        let(:other_parcel) { parcel_of(paid_order) }

        def notice_with_order_id(order_id, body: ship_notice_xml(number: parcel.number, order_id: order_id))
          ship_notice("/shipstation", number: parcel.number, body: body, headers: credentials(integration))
        end

        it("fulfils the parcel when the OrderID matches") do
          notice_with_order_id(parcel.id)
          expect(parcel.reload.status).to eq("fulfilled")
        end

        it("answers an OrderID from another order with 400") do
          notice_with_order_id(other_parcel.id)
          expect(response).to have_http_status(:bad_request)
        end

        it("explains an OrderID from another order") do
          notice_with_order_id(other_parcel.id)
          expect(response.body).to eq("Shipment #{parcel.number} does not match order id #{other_parcel.id}")
        end

        it("ignores an OrderID that is not a whole number") do
          notice_with_order_id("12abc")
          expect(response).to have_http_status(:ok)
        end

        it("ignores a body that is not well-formed XML") do
          notice_with_order_id(other_parcel.id, body: "<ShipNotice><OrderID>#{other_parcel.id}</OrderID>")
          expect(response).to have_http_status(:ok)
        end

        it("ignores a body over 64 KB") do
          padded = ship_notice_xml(number: parcel.number, order_id: other_parcel.id)
            .sub("</ShipNotice>", "<InternalNotes>#{"x" * 64.kilobytes}</InternalNotes></ShipNotice>")
          notice_with_order_id(other_parcel.id, body: padded)
          expect(response).to have_http_status(:ok)
        end
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

      # Only the path names an integration, so the bare URL stays the default
      # store's whatever the query string says.
      it("ignores an integration id in the bare URL's query string") do
        get "/shipstation.xml", params: {integration_id: other_integration.prefixed_id}, headers: credentials(other_integration)
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

      it("answers a ship notice for an inactive integration's URL with 404") do
        other_integration.update!(active: false)
        ship_notice(other_path, number: parcel_of(other_order).number, headers: credentials(other_integration))
        expect(response).to have_http_status(:not_found)
      end

      context "when unpermitted parameters raise" do
        around do |example|
          previous = ActionController::Parameters.action_on_unpermitted_parameters
          ActionController::Parameters.action_on_unpermitted_parameters = :raise
          example.run
        ensure
          ActionController::Parameters.action_on_unpermitted_parameters = previous
        end

        # The integration id, and whatever else ShipStation adds to the query,
        # are not part of the notice.
        it("still fulfils the other store's parcel") do
          parcel = parcel_of(other_order)
          ship_notice(other_path, number: parcel.number, service: "Ground", headers: credentials(other_integration))
          expect(parcel.reload.status).to eq("fulfilled")
        end
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
