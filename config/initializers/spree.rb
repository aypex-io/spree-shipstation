# frozen_string_literal: true

# Spree resolves registered entries to classes itself, so the class name string
# avoids loading the model before the app has finished booting.
Rails.application.config.after_initialize do
  Spree.integrations << "Spree::Integrations::Shipstation"
end
