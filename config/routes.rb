# frozen_string_literal: true

# ShipStation pulls orders and posts ship notices to the same URL. The bare path
# belongs to the default store. The path that names an integration (its prefixed
# id) belongs to that integration's store, which is how a second store gets an
# endpoint of its own.
#
# The export is XML whether or not the URL ends in +.xml+. Without the default,
# a pull that sends a browser-like Accept header would be refused with a 406.
Spree::Core::Engine.add_routes do
  get "/shipstation(.:format)", to: "shipstation#export", defaults: {format: "xml"}
  post "/shipstation(.:format)", to: "shipstation#shipnotify"

  get "/shipstation/:integration_id(.:format)", to: "shipstation#export", defaults: {format: "xml"}
  post "/shipstation/:integration_id(.:format)", to: "shipstation#shipnotify"
end
