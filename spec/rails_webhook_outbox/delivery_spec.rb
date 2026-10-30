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

  describe "payload version" do
    after { RailsWebhookOutbox.reset_configuration! }

    it "is stamped with the default version on create" do
      delivery.save!
      expect(delivery.payload_version).to eq(1)
    end

    it "is stamped with the event's configured version on create" do
      RailsWebhookOutbox.configure { |c| c.payload_versions = { delivery.event => 2 } }
      delivery.save!
      expect(delivery.payload_version).to eq(2)
    end

    it "does not overwrite a version set explicitly" do
      delivery.payload_version = 5
      delivery.save!
      expect(delivery.payload_version).to eq(5)
    end

    it "keeps the original version when the config changes before a retry" do
      delivery.save!
      RailsWebhookOutbox.configure { |c| c.payload_versions = { delivery.event => 3 } }
      delivery.update!(attempts: 1)
      expect(delivery.reload.payload_version).to eq(1)
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

  describe "turbo broadcasts" do
    before { delivery.save! }

    it "broadcasts a row replace to the shared deliveries stream on update" do
      assert_broadcasts("rails_webhook_outbox_deliveries", 1) do
        delivery.update!(status: :delivered)
      end
    end

    it "broadcasts a detail replace to the delivery's own stream on update" do
      assert_broadcasts(delivery.to_gid_param, 1) do
        delivery.update!(status: :delivered)
      end
    end

    it "does not broadcast on create" do
      new_delivery = described_class.new(subscription: subscription, event: "order.created", payload: { id: 2 })
      assert_no_broadcasts("rails_webhook_outbox_deliveries") { new_delivery.save! }
    end

    it "renders the row partial with its link into the shared stream broadcast" do
      messages = capture_broadcasts("rails_webhook_outbox_deliveries") { delivery.update!(status: :delivered) }

      expect(messages.join).to include(%(target="#{ActionView::RecordIdentifier.dom_id(delivery)}"))
      expect(messages.join).to include(%(href="/rails_webhook_outbox/deliveries/#{delivery.id}"))
    end

    it "renders the detail partial into the delivery's own stream broadcast" do
      messages = capture_broadcasts(delivery.to_gid_param) { delivery.update!(status: :delivered) }

      expect(messages.join).to include(%(target="#{ActionView::RecordIdentifier.dom_id(delivery, :detail)}"))
      expect(messages.join).to include("Delivered")
    end

    it "includes the attempt timeline in the detail broadcast" do
      delivery.delivery_attempts.create!(attempt_number: 1, outcome: :delivered, response_code: 200)
      messages = capture_broadcasts(delivery.to_gid_param) { delivery.update!(status: :delivered) }

      expect(messages.join).to include("Timeline", "Attempt 1", "HTTP 200")
    end
  end

  describe "overview broadcasts" do
    let(:stream) { RailsWebhookOutbox::Overview::STREAM }

    it "broadcasts the stats and recent failures on create" do
      new_delivery = described_class.new(subscription: subscription, event: "order.created", payload: { id: 2 })
      assert_broadcasts(stream, 2) { new_delivery.save! }
    end

    it "broadcasts the stats and recent failures on update" do
      delivery.save!
      assert_broadcasts(stream, 2) { delivery.update!(status: :failed) }
    end

    it "broadcasts the stats and recent failures on destroy" do
      delivery.save!
      assert_broadcasts(stream, 2) { delivery.destroy! }
    end

    it "renders the new counts into the broadcast" do
      delivery.save!
      messages = capture_broadcasts(stream) { delivery.update!(status: :failed) }

      expect(messages.join).to include("rwo-overview-stats", "rwo-overview-failures", "order.created")
    end
  end

  describe "latency" do
    let(:now) { Time.current }

    def create_delivered(latency:, delivered_at: now)
      described_class.create!(
        subscription: subscription, event: "order.created", payload: { id: 1 },
        status: :delivered, created_at: delivered_at - latency, delivered_at: delivered_at
      )
    end

    describe "#latency" do
      it "is the seconds between creation and delivery" do
        expect(create_delivered(latency: 2.5).latency).to be_within(0.001).of(2.5)
      end

      it "is nil while pending" do
        expect(delivery.latency).to be_nil
      end

      it "is nil for a delivered record with no delivered_at" do
        delivery.status = :delivered
        expect(delivery.latency).to be_nil
      end
    end

    describe ".latencies" do
      it "returns sorted latencies of deliveries delivered within the window" do
        create_delivered(latency: 3)
        create_delivered(latency: 1)
        create_delivered(latency: 9, delivered_at: now - 2.days)
        delivery.save!

        expect(described_class.latencies.map(&:round)).to eq([1, 3])
        expect(described_class.latencies(window: 3.days).map(&:round)).to eq([1, 3, 9])
      end
    end

    describe "sample cap" do
      after { RailsWebhookOutbox.reset_configuration! }

      it "uses only the most recent config.latency_sample_size deliveries" do
        RailsWebhookOutbox.config.latency_sample_size = 2
        create_delivered(latency: 100, delivered_at: now - 3.hours)
        create_delivered(latency: 1, delivered_at: now - 2.hours)
        create_delivered(latency: 3, delivered_at: now - 1.hour)

        expect(described_class.latencies.map(&:round)).to eq([1, 3])
      end
    end

    describe ".average_latency and .p95_latency" do
      it "are nil with no delivered deliveries" do
        expect(described_class.average_latency).to be_nil
        expect(described_class.p95_latency).to be_nil
      end

      it "average the latencies and pick the nearest-rank 95th percentile" do
        (1..20).each { |seconds| create_delivered(latency: seconds) }

        expect(described_class.average_latency).to be_within(0.01).of(10.5)
        expect(described_class.p95_latency).to be_within(0.01).of(19)
      end
    end
  end

  describe ".prune" do
    def create_aged(status:, age:)
      record = described_class.create!(subscription: subscription, event: "order.created", payload: { id: 1 }, status: status)
      record.update_column(:created_at, age.ago)
      record
    end

    it "deletes delivered and failed deliveries older than the cutoff and returns the count" do
      old_delivered = create_aged(status: :delivered, age: 10.days)
      old_failed = create_aged(status: :failed, age: 10.days)

      expect(described_class.prune(older_than: 7.days)).to eq(2)
      expect(described_class.exists?(old_delivered.id)).to be false
      expect(described_class.exists?(old_failed.id)).to be false
    end

    it "keeps recent deliveries and never deletes pending ones" do
      recent = create_aged(status: :delivered, age: 1.day)
      pending = create_aged(status: :pending, age: 10.days)

      expect(described_class.prune(older_than: 7.days)).to eq(0)
      expect(described_class.exists?(recent.id)).to be true
      expect(described_class.exists?(pending.id)).to be true
    end

    it "removes the delivery attempts along with their deliveries" do
      old = create_aged(status: :delivered, age: 10.days)
      old.delivery_attempts.create!(attempt_number: 1, outcome: :delivered, duration_ms: 5)

      expect { described_class.prune(older_than: 7.days) }
        .to change(RailsWebhookOutbox::DeliveryAttempt, :count).by(-1)
    end

    it "deletes in batches until nothing old is left" do
      5.times { create_aged(status: :delivered, age: 10.days) }
      keeper = create_aged(status: :delivered, age: 1.day)

      expect(described_class.prune(older_than: 7.days, batch_size: 2)).to eq(5)
      expect(described_class.pluck(:id)).to eq([keeper.id])
    end

    it "handles a total that is an exact multiple of the batch size" do
      4.times { create_aged(status: :failed, age: 10.days) }

      expect(described_class.prune(older_than: 7.days, batch_size: 2)).to eq(4)
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