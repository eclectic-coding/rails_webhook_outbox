require "rails/generators"
require "rails/generators/active_record"

module RailsWebhookOutbox
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "Creates a RailsWebhookOutbox initializer and copies migrations to your application."

      def self.next_migration_number(dirname)
        ActiveRecord::Generators::Base.next_migration_number(dirname)
      end

      def copy_migrations
        migration_template(
          "create_webhook_outbox_subscriptions.rb",
          "db/migrate/create_webhook_outbox_subscriptions.rb"
        )
        migration_template(
          "create_webhook_outbox_deliveries.rb",
          "db/migrate/create_webhook_outbox_deliveries.rb"
        )
      end

      def create_initializer
        template "initializer.rb", "config/initializers/rails_webhook_outbox.rb"
      end
    end
  end
end
