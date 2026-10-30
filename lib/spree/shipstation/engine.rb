# frozen_string_literal: true

module Spree
  module Shipstation
    ##
    # Rails engine for the ShipStation integration. It makes the gem's +app+ and
    # +config+ directories part of the host application.
    #
    class Engine < ::Rails::Engine
      require "spree/core"
      isolate_namespace Spree

      # Deliberately not "spree-shipstation": engine_name generates route helper
      # prefixes and must be a valid Ruby identifier, so it cannot contain a dash.
      engine_name "spree_shipstation"

      # use rspec for tests
      config.generators do |g|
        g.test_framework :rspec
      end
    end
  end
end
