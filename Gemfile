# frozen_string_literal: true

source "https://rubygems.org"

gem "benchmark"
gem "brakeman", require: false
gem "bundler-audit", require: false
gem "rspec-xsd"
# Constrained here, not only in the gemspec: under Bundler 2 an unconstrained
# entry in the Gemfile overrides the gemspec and resolves 0.6.3, which cannot
# load on Spree 6.
gem "spree_dev_tools", ">= 1.0.0.beta2"
gem "standard"
gem "sqlite3"

# CI runs a matrix of Spree versions. SPREE_VERSION pins one (e.g. "6.0.0");
# left unset, Bundler resolves the newest release the gemspec allows.
spree_version = ENV.fetch("SPREE_VERSION", "")
gem "spree", spree_version unless spree_version.empty?

gemspec
