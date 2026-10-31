# frozen_string_literal: true

module Spree
  module Shipstation
    # Major version tracks Spree's major version: 6.x supports Spree 6; 5.0.x
    # lives on +5-0-stable+.
    VERSION = "6.0.2"

    ##
    # Gem version as a comparable +Gem::Version+.
    #
    # @return [Gem::Version]
    #
    def self.version
      Gem::Version.new(VERSION)
    end
  end
end
