require "rails/generators"

module RailsWebhookOutbox
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Creates a RailsWebhookOutbox initializer. The engine supplies its own migrations; run `rails db:migrate` afterwards."

      def create_initializer
        template "initializer.rb", "config/initializers/rails_webhook_outbox.rb"
      end
    end
  end
end
