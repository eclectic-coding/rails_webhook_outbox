module RailsWebhookOutbox
  class Engine < ::Rails::Engine
    isolate_namespace RailsWebhookOutbox
    config.generators.api_only = true
  end
end
