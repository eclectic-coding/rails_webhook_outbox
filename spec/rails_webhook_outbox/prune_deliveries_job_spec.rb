require "rails_helper"

RSpec.describe RailsWebhookOutbox::PruneDeliveriesJob do
  include ActiveJob::TestHelper

  let(:subscription) do
    RailsWebhookOutbox::Subscription.create!(url: "https://example.com/webhooks", events: ["order.created"])
  end

  def create_aged(status:, age:)
    record = RailsWebhookOutbox::Delivery.create!(
      subscription: subscription, event: "order.created", payload: { id: 1 }, status: status
    )
    record.update_column(:created_at, age.ago)
    record
  end

  after { RailsWebhookOutbox.reset_configuration! }

  it "uses the configured delivery job queue" do
    RailsWebhookOutbox.configure { |c| c.delivery_job_queue = :priority }

    expect(described_class.new.queue_name).to eq("priority")
  end

  context "when retention_period is nil" do
    it "deletes nothing" do
      old = create_aged(status: :delivered, age: 400.days)

      described_class.perform_now

      expect(RailsWebhookOutbox::Delivery.exists?(old.id)).to be true
    end
  end

  context "when retention_period is set" do
    before { RailsWebhookOutbox.configure { |c| c.retention_period = 30.days } }

    it "prunes finished deliveries older than the period" do
      old_delivered = create_aged(status: :delivered, age: 31.days)
      old_failed = create_aged(status: :failed, age: 31.days)

      described_class.perform_now

      expect(RailsWebhookOutbox::Delivery.exists?(old_delivered.id)).to be false
      expect(RailsWebhookOutbox::Delivery.exists?(old_failed.id)).to be false
    end

    it "keeps recent and pending deliveries" do
      recent = create_aged(status: :delivered, age: 5.days)
      pending = create_aged(status: :pending, age: 90.days)

      described_class.perform_now

      expect(RailsWebhookOutbox::Delivery.exists?(recent.id)).to be true
      expect(RailsWebhookOutbox::Delivery.exists?(pending.id)).to be true
    end

    it "removes the attempts of pruned deliveries" do
      old = create_aged(status: :delivered, age: 31.days)
      old.delivery_attempts.create!(attempt_number: 1, outcome: :delivered, duration_ms: 5)

      expect { described_class.perform_now }.to change(RailsWebhookOutbox::DeliveryAttempt, :count).by(-1)
    end

    it "logs how many deliveries were pruned" do
      create_aged(status: :delivered, age: 31.days)
      messages = []
      allow(Rails.logger).to receive(:info) { |*args, &blk| messages << (blk ? blk.call : args.first).to_s }

      described_class.perform_now

      expect(messages.join("\n")).to include("[RailsWebhookOutbox] pruned deliveries=1 older_than=30 days")
    end
  end
end
