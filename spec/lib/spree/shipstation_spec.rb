# frozen_string_literal: true

require "spec_helper"

RSpec.describe(Spree::Shipstation) do
  describe "VERSION" do
    it("is defined") { expect(Spree::Shipstation::VERSION).to be_present }

    it("is version 6.0.3") do
      expect(Spree::Shipstation::VERSION).to eq("6.0.3")
    end
  end

  describe "Spree compatibility" do
    it("targets Spree 6") do
      expect(Gem::Requirement.new("~> 6.0")).to be_satisfied_by(Gem::Version.new(Spree.version))
    end
  end

  describe ".version" do
    it("returns the VERSION as a Gem::Version") do
      expect(Spree::Shipstation.version).to eq(Gem::Version.new(Spree::Shipstation::VERSION))
    end
  end
end
