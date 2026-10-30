# frozen_string_literal: true

module Spree
  module Shipstation
    ##
    # Rails engine that loads this extension's decorator files.
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

      def self.activate
        # Three levels up from lib/spree/shipstation/ to reach the gem root.
        Dir.glob(File.join(File.dirname(__FILE__), "../../../app/**/*_decorator*.rb")).sort.each do |c|
          Rails.configuration.cache_classes ? require(c) : load(c)
        end
      end

      config.to_prepare(&method(:activate).to_proc)
    end
  end
end
