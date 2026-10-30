# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift lib unless $LOAD_PATH.include?(lib)

require "spree/shipstation/version"

Gem::Specification.new do |s|
  s.platform = Gem::Platform::RUBY
  s.name = "spree-shipstation"
  s.version = Spree::Shipstation.version
  s.summary = "ShipStation integration for Spree e-commerce"
  s.description = "Connects Spree stores to ShipStation via an XML export endpoint and shipnotify webhook, enabling automated label creation and shipment tracking."
  s.required_ruby_version = ">= 3.3"

  s.author = "Matthew Kennedy"
  s.email = "m.kennedy@me.com"
  s.homepage = "https://github.com/aypex-io/spree-shipstation"
  s.license = "MIT"

  s.metadata = {
    "source_code_uri" => s.homepage,
    "bug_tracker_uri" => "#{s.homepage}/issues",
    "changelog_uri" => "#{s.homepage}/blob/main/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }

  s.files = `git ls-files`.split("\n").reject { |f| f.match(/^spec/) && !f.match(%r{^spec/fixtures}) }
  s.require_path = "lib"

  s.add_dependency "pagy", ">= 43.6", "< 45"
  s.add_dependency "spree", "~> 6.0"
end
