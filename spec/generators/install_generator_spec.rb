require "rails_helper"
require "rails/generators/testing/behavior"
require "generators/rails_webhook_outbox/install/install_generator"

RSpec.describe RailsWebhookOutbox::Generators::InstallGenerator do
  include Rails::Generators::Testing::Behavior
  include FileUtils

  tests RailsWebhookOutbox::Generators::InstallGenerator
  destination File.expand_path("../../tmp/generator_test", __dir__)

  before { prepare_destination }
  after  { rm_rf(destination_root) }

  def file(relative)
    File.expand_path(relative, destination_root)
  end

  it "copies the subscriptions migration" do
    run_generator
    path = migration_file_name("db/migrate/create_webhook_outbox_subscriptions.rb")
    expect(path).not_to be_nil
    expect(File.read(path)).to include("create_table :webhook_outbox_subscriptions")
  end

  it "copies the deliveries migration" do
    run_generator
    path = migration_file_name("db/migrate/create_webhook_outbox_deliveries.rb")
    expect(path).not_to be_nil
    expect(File.read(path)).to include("create_table :webhook_outbox_deliveries")
  end

  it "stamps migrations with the current Rails migration version" do
    run_generator
    path = migration_file_name("db/migrate/create_webhook_outbox_subscriptions.rb")
    expect(File.read(path)).to include("ActiveRecord::Migration[#{ActiveRecord::Migration.current_version}]")
  end

  it "creates the initializer" do
    run_generator
    expect(File.exist?(file("config/initializers/rails_webhook_outbox.rb"))).to be true
    expect(File.read(file("config/initializers/rails_webhook_outbox.rb")))
      .to include("RailsWebhookOutbox.configure")
  end

  it "includes all configuration options in the initializer" do
    run_generator
    content = File.read(file("config/initializers/rails_webhook_outbox.rb"))
    %w[
      config.events
      config.signing_algorithm
      config.signing_header
      config.max_retries
      config.retry_backoff
      config.request_timeout
      config.delivery_job_queue
    ].each do |option|
      expect(content).to include(option)
    end
  end
end