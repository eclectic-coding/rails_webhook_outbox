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
end