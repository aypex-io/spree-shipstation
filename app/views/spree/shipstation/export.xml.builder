xml.instruct!

xml.Orders(pages: @pagy.pages) do
  @fulfillments.each do |fulfillment|
    order = Spree::Shipstation::Export::OrderPresenter.new(fulfillment)

    xml.Order do
      xml.OrderID order.order_id
      xml.OrderNumber order.order_number

      xml.OrderDate order.order_date
      xml.OrderStatus order.order_status
      xml.LastModified order.last_modified

      xml.ShippingMethod order.shipping_method_name
      xml.OrderTotal order.order_total
      xml.TaxAmount order.tax_total
      xml.ShippingAmount order.ship_total
      xml.CustomField1 order.custom_field_1

      xml.Customer do
        xml.CustomerCode order.customer_code
        Spree::Shipstation::ExportHelper.bill_address(xml, order.bill_address)
        Spree::Shipstation::ExportHelper.ship_address(xml, order.ship_address)
      end

      xml.Items do
        order.items.each do |item|
          weight = item.weight
          # The thumbnail may be a video. Its still image is the poster, and is
          # nil for an embedded video, which has no attachment to link to.
          still_image = item.image&.still_image

          xml.Item do
            xml.SKU item.sku
            xml.Name item.name

            image_url = still_image && url_for(still_image)
            xml.ImageUrl image_url if image_url

            xml.Weight weight.value
            xml.WeightUnits weight.units
            xml.Quantity item.quantity
            xml.UnitPrice item.unit_price

            if item.option_values.present?
              xml.Options do
                item.option_values.each do |name, value|
                  xml.Option do
                    xml.Name name
                    xml.Value value
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
