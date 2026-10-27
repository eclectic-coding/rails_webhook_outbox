require "rails_helper"

RSpec.describe RailsWebhookOutbox::Overview do
  subject(:overview) { described_class.new }

  let!(:subscription) do
    RailsWebhookOutbox::Subscription.create!(url: "https://example.com/webhooks", events: ["order.created"])
  end

  def create_delivery(status:, created_at: Time.current)
    RailsWebhookOutbox::Delivery.create!(
      subscription: subscription, event: "order.created", payload: { id: 1 }, status: status, created_at: created_at
    )
  end

  describe "#subscription_count and #active_subscription_count" do
    before do
      RailsWebhookOutbox::Subscription.create!(url: "https://example.com/other", events: ["order.created"], active: false)
    end

    it "counts all and active subscriptions" do
      expect(overview.subscription_count).to eq(2)
      expect(overview.active_subscription_count).to eq(1)
    end
  end

  describe "#delivery_count" do
    before do
      create_delivery(status: :delivered)
      create_delivery(status: :delivered)
      create_delivery(status: :failed)
    end

    it "counts deliveries by status" do
      expect(overview.delivery_count(:delivered)).to eq(2)
      expect(overview.delivery_count("failed")).to eq(1)
    end

    it "returns zero for a status with no deliveries" do
      expect(overview.delivery_count(:pending)).to eq(0)
    end
  end

  describe "#recent_failures" do
    it "returns only failed deliveries, newest first" do
      older = create_delivery(status: :failed, created_at: 2.hours.ago)
      newer = create_delivery(status: :failed, created_at: 1.hour.ago)
      create_delivery(status: :delivered)

      expect(overview.recent_failures).to eq([newer, older])
    end

    it "is limited to RECENT_FAILURES_LIMIT" do
      (described_class::RECENT_FAILURES_LIMIT + 1).times { create_delivery(status: :failed) }

      expect(overview.recent_failures.size).to eq(described_class::RECENT_FAILURES_LIMIT)
    end
  end

  describe ".broadcast_stats" do
    it "broadcasts a stats replace to the overview stream" do
      assert_broadcasts(described_class::STREAM, 1) { described_class.broadcast_stats }
    end
  end

  describe ".broadcast_recent_failures" do
    it "broadcasts a recent failures replace to the overview stream" do
      assert_broadcasts(described_class::STREAM, 1) { described_class.broadcast_recent_failures }
    end
  end
end
