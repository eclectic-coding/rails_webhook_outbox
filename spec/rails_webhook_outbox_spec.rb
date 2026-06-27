require "rails_helper"

RSpec.describe RailsWebhookOutbox do
  include ActiveJob::TestHelper

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

  describe ".dispatch" do
    let(:payload) { { id: 1, total: "99.00" } }

    let!(:subscription) do
      RailsWebhookOutbox::Subscription.create!(
        url: "https://example.com/hooks",
        events: ["order.created"],
        active: true
      )
    end

    it "creates a Delivery for each matching active subscription" do
      expect { described_class.dispatch("order.created", payload) }
        .to change(RailsWebhookOutbox::Delivery, :count).by(1)
    end

    it "enqueues a DeliveryJob for each matching active subscription" do
      expect { described_class.dispatch("order.created", payload) }
        .to have_enqueued_job(RailsWebhookOutbox::DeliveryJob)
    end

    it "stores the event and payload on the delivery" do
      described_class.dispatch("order.created", payload)
      delivery = RailsWebhookOutbox::Delivery.last
      expect(delivery.event).to eq("order.created")
      expect(delivery.payload).to eq({ "id" => 1, "total" => "99.00" })
    end

    it "dispatches to multiple matching subscriptions" do
      RailsWebhookOutbox::Subscription.create!(
        url: "https://second.example.com/hooks",
        events: ["order.created"],
        active: true
      )
      expect { described_class.dispatch("order.created", payload) }
        .to have_enqueued_job(RailsWebhookOutbox::DeliveryJob).twice
    end

    it "skips subscriptions that do not subscribe to the event" do
      RailsWebhookOutbox::Subscription.create!(
        url: "https://other.example.com/hooks",
        events: ["payment.completed"],
        active: true
      )
      expect { described_class.dispatch("order.created", payload) }
        .to change(RailsWebhookOutbox::Delivery, :count).by(1)
    end

    it "skips inactive subscriptions" do
      subscription.update!(active: false)
      expect { described_class.dispatch("order.created", payload) }
        .not_to have_enqueued_job(RailsWebhookOutbox::DeliveryJob)
    end

    it "does nothing when no subscriptions match" do
      expect { described_class.dispatch("unknown.event", payload) }
        .not_to have_enqueued_job(RailsWebhookOutbox::DeliveryJob)
    end
  end
end