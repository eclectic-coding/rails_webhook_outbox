require "turbo-rails"
require "importmap-rails"

module RailsWebhookOutbox
  class Engine < ::Rails::Engine
    isolate_namespace RailsWebhookOutbox
    config.generators.api_only = true

    # The dashboard's button_to forms submit PATCH as POST plus a hidden _method field.
    # API-only host apps don't include this middleware, so the engine brings its own.
    middleware.use Rack::MethodOverride

    initializer :append_migrations do |app|
      unless app.root.to_s.match?(__dir__)
        RailsWebhookOutbox::Engine.config.paths["db/migrate"].expanded.each do |path|
          app.config.paths["db/migrate"] << path
        end
      end
    end

    initializer "rails_webhook_outbox.assets" do |app|
      if app.config.respond_to?(:assets)
        app.config.assets.paths << RailsWebhookOutbox::Engine.root.join("app/javascript")
      end
    end

    initializer "rails_webhook_outbox.importmap", before: "importmap" do |app|
      if app.config.respond_to?(:importmap)
        app.config.importmap.paths << RailsWebhookOutbox::Engine.root.join("config/importmap.rb")
        app.config.importmap.cache_sweepers << RailsWebhookOutbox::Engine.root.join("app/javascript")
      end
    end
  end
end
