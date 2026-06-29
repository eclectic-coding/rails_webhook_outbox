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

  describe ".validate_event!" do
    context "when no events are configured" do
      it "does not raise for any event" do
        expect { described_class.validate_event!("anything.goes") }.not_to raise_error
      end
    end

    context "when events are configured" do
      before { described_class.configure { |c| c.events = %w[order.created order.updated] } }

      it "does not raise for a registered event" do
        expect { described_class.validate_event!("order.created") }.not_to raise_error
      end

      it "raises ArgumentError for an unregistered event" do
        expect { described_class.validate_event!("payment.failed") }
          .to raise_error(ArgumentError, /Unknown event "payment\.failed"/)
      end

      it "includes the registered events in the error message" do
        expect { described_class.validate_event!("payment.failed") }
          .to raise_error(ArgumentError, /order\.created, order\.updated/)
      end
    end
  end

  describe ".validate_payload_size!" do
    let(:small_payload) { { id: 1 } }
    let(:large_payload) { { data: "x" * 70_000 } }

    it "does not raise for a payload within the default limit" do
      expect { described_class.validate_payload_size!(small_payload) }.not_to raise_error
    end

    it "raises PayloadSizeError when the payload exceeds the limit" do
      expect { described_class.validate_payload_size!(large_payload) }
        .to raise_error(RailsWebhookOutbox::PayloadSizeError, /too large/)
    end

    it "includes size and limit in the error message" do
      described_class.configure { |c| c.max_payload_size = 10 }
      expect { described_class.validate_payload_size!({ data: "hello world" }) }
        .to raise_error(RailsWebhookOutbox::PayloadSizeError, /bytes exceeds the 10-byte limit/)
    end

    it "skips validation when max_payload_size is nil" do
      described_class.configure { |c| c.max_payload_size = nil }
      expect { described_class.validate_payload_size!(large_payload) }.not_to raise_error
    end

    it "skips validation when max_payload_size is 0" do
      described_class.configure { |c| c.max_payload_size = 0 }
      expect { described_class.validate_payload_size!(large_payload) }.not_to raise_error
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

    context "when events are configured" do
      before { described_class.configure { |c| c.events = %w[order.created] } }

      it "raises ArgumentError for an unregistered event" do
        expect { described_class.dispatch("payment.failed", payload) }
          .to raise_error(ArgumentError, /Unknown event/)
      end

      it "dispatches a registered event without error" do
        expect { described_class.dispatch("order.created", payload) }
          .to have_enqueued_job(RailsWebhookOutbox::DeliveryJob)
      end
    end

    context "when the payload exceeds max_payload_size" do
      before { described_class.configure { |c| c.max_payload_size = 10 } }

      it "raises PayloadSizeError before enqueuing" do
        expect { described_class.dispatch("order.created", { data: "this is too large" }) }
          .to raise_error(RailsWebhookOutbox::PayloadSizeError)
      end
    end
  end
end