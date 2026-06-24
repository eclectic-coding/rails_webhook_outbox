require "rails_helper"

RSpec.describe RailsWebhookOutbox do
  after { described_class.reset_configuration! }

  describe ".configuration" do
    it "returns a Configuration instance" do
      expect(described_class.configuration).to be_a(RailsWebhookOutbox::Configuration)
    end

    it "memoizes the instance" do
      expect(described_class.configuration).to be(described_class.configuration)
    end
  end

  describe ".config" do
    it "is an alias for .configuration" do
      expect(described_class.config).to be(described_class.configuration)
    end
  end

  describe ".configure" do
    it "yields the configuration" do
      described_class.configure do |config|
        config.events = %w[order.created]
        config.max_retries = 3
      end

      expect(described_class.config.events).to eq(%w[order.created])
      expect(described_class.config.max_retries).to eq(3)
    end
  end

  describe ".reset_configuration!" do
    it "resets to defaults" do
      described_class.configure { |c| c.max_retries = 3 }
      described_class.reset_configuration!
      expect(described_class.config.max_retries).to eq(8)
    end
  end
end