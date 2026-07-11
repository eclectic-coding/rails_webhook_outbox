require "rails_helper"

RSpec.describe RailsWebhookOutbox::Engine do
  describe "append_migrations initializer" do
    let(:initializer) { described_class.initializers.find { |i| i.name == :append_migrations } }

    it "appends engine migration paths to the host app" do
      app = Rails.application
      paths_before = app.config.paths["db/migrate"].to_a.dup

      initializer.run(app)

      engine_path = RailsWebhookOutbox::Engine.config.paths["db/migrate"].expanded.first
      expect(app.config.paths["db/migrate"].to_a).to include(engine_path)

      app.config.paths["db/migrate"].instance_variable_get(:@paths).replace(paths_before)
    end

    it "skips appending when the app root is inside the engine" do
      fake_app = instance_double(Rails::Application,
        root: Pathname.new(File.expand_path("../../lib/rails_webhook_outbox", __dir__)),
        config: Rails.application.config)

      expect(fake_app.config).not_to receive(:paths)

      initializer.run(fake_app)
    end
  end

  describe "rails_webhook_outbox.assets initializer" do
    let(:initializer) { described_class.initializers.find { |i| i.name == "rails_webhook_outbox.assets" } }

    it "adds the engine's javascript path to app.config.assets.paths" do
      app = Rails.application
      paths_before = app.config.assets.paths.dup

      initializer.run(app)

      expect(app.config.assets.paths).to include(RailsWebhookOutbox::Engine.root.join("app/javascript"))

      app.config.assets.paths.replace(paths_before)
    end

    it "does nothing when the host app has no assets config" do
      fake_app = Struct.new(:config).new(Object.new)
      expect { initializer.run(fake_app) }.not_to raise_error
    end
  end

  describe "rails_webhook_outbox.importmap initializer" do
    let(:initializer) { described_class.initializers.find { |i| i.name == "rails_webhook_outbox.importmap" } }

    it "registers the engine's importmap path and cache sweeper" do
      app = Rails.application
      paths_before = app.config.importmap.paths.dup
      sweepers_before = app.config.importmap.cache_sweepers.dup

      initializer.run(app)

      expect(app.config.importmap.paths).to include(RailsWebhookOutbox::Engine.root.join("config/importmap.rb"))
      expect(app.config.importmap.cache_sweepers).to include(RailsWebhookOutbox::Engine.root.join("app/javascript"))

      app.config.importmap.paths.replace(paths_before)
      app.config.importmap.cache_sweepers.replace(sweepers_before)
    end

    it "does nothing when the host app has no importmap config" do
      fake_app = Struct.new(:config).new(Object.new)
      expect { initializer.run(fake_app) }.not_to raise_error
    end
  end
end