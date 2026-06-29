require "rails_helper"

module RailsWebhookOutbox
  class Subscription < ApplicationRecord
    self.table_name = "webhook_outbox_subscriptions"
  end unless const_defined?(:Subscription)
end

RSpec.describe RailsWebhookOutbox::Delivery do
  let(:subscription) do
    RailsWebhookOutbox::Subscription.create!(
      url: "https://example.com/webhooks",
      secret: "test-secret-abc123",
      events: ["order.created"],
      active: true
    )
  end

  let(:delivery) do
    described_class.new(
      subscription: subscription,
      event: "order.created",
      payload: { id: 1 }
    )
  end

  describe "associations" do
    it "belongs to a subscription" do
      expect(delivery.subscription).to eq(subscription)
    end
  end

  describe "validations" do
    it "is valid with subscription, event, and payload" do
      expect(delivery).to be_valid
    end

    it "is invalid without an event" do
      delivery.event = nil
      expect(delivery).not_to be_valid
      expect(delivery.errors[:event]).to include("can't be blank")
    end

    it "is invalid without a payload" do
      delivery.payload = nil
      expect(delivery).not_to be_valid
      expect(delivery.errors[:payload]).to include("can't be blank")
    end

    it "is invalid without a subscription" do
      delivery.subscription = nil
      expect(delivery).not_to be_valid
      expect(delivery.errors[:subscription]).to be_present
    end
  end

  describe "idempotency key" do
    it "generates a UUID on create when none is provided" do
      delivery.save!
      expect(delivery.idempotency_key).to match(/\A[0-9a-f-]{36}\z/)
    end

    it "does not overwrite a manually set idempotency key" do
      delivery.idempotency_key = "my-custom-key"
      delivery.save!
      expect(delivery.idempotency_key).to eq("my-custom-key")
    end

    it "is invalid without an idempotency key" do
      delivery.idempotency_key = nil
      delivery.save # trigger before_validation
      delivery.idempotency_key = nil
      expect(delivery).not_to be_valid
      expect(delivery.errors[:idempotency_key]).to be_present
    end
  end

  describe "status enum" do
    it "defaults to pending" do
      delivery.save!
      expect(delivery).to be_pending
    end

    it "can be set to delivered" do
      delivery.save!
      delivery.delivered!
      expect(delivery).to be_delivered
    end

    it "can be set to failed" do
      delivery.save!
      delivery.failed!
      expect(delivery).to be_failed
    end
  end

  describe "scopes" do
    before { delivery.save! }

    describe ".retryable" do
      it "returns pending deliveries" do
        expect(described_class.retryable).to include(delivery)
      end

      it "excludes delivered deliveries" do
        delivery.delivered!
        expect(described_class.retryable).not_to include(delivery)
      end

      it "excludes failed deliveries" do
        delivery.failed!
        expect(described_class.retryable).not_to include(delivery)
      end
    end

    describe ".delivered" do
      it "returns delivered deliveries" do
        delivery.delivered!
        expect(described_class.delivered).to include(delivery)
      end

      it "excludes pending deliveries" do
        expect(described_class.delivered).not_to include(delivery)
      end
    end

    describe ".failed" do
      it "returns failed deliveries" do
        delivery.failed!
        expect(described_class.failed).to include(delivery)
      end

      it "excludes pending deliveries" do
        expect(described_class.failed).not_to include(delivery)
      end
    end
  end
end