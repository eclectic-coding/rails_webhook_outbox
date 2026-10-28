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

    it "reads both counts with a single query" do
      queries = []
      counter = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        overview.subscription_count
        overview.active_subscription_count
      end

      expect(queries.size).to eq(1)
    end

    it "returns zero when there are no subscriptions" do
      RailsWebhookOutbox::Subscription.delete_all

      expect(overview.subscription_count).to eq(0)
      expect(overview.active_subscription_count).to eq(0)
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

  describe "#average_latency and #p95_latency" do
    it "are nil with no delivered deliveries" do
      expect(overview.average_latency).to be_nil
      expect(overview.p95_latency).to be_nil
    end

    it "cover deliveries delivered in the last 24 hours" do
      [2, 4].each do |seconds|
        RailsWebhookOutbox::Delivery.create!(
          subscription: subscription, event: "order.created", payload: { id: 1 }, status: :delivered,
          created_at: Time.current - seconds, delivered_at: Time.current
        )
      end
      RailsWebhookOutbox::Delivery.create!(
        subscription: subscription, event: "order.created", payload: { id: 1 }, status: :delivered,
        created_at: 3.days.ago - 60, delivered_at: 3.days.ago
      )

      expect(overview.average_latency).to be_within(0.01).of(3)
      expect(overview.p95_latency).to be_within(0.01).of(4)
    end
  end

  describe "latency caching" do
    include ActiveSupport::Testing::TimeHelpers

    let(:cache) { ActiveSupport::Cache::MemoryStore.new }

    before { allow(Rails).to receive(:cache).and_return(cache) }

    after { RailsWebhookOutbox.reset_configuration! }

    def deliver(latency)
      RailsWebhookOutbox::Delivery.create!(
        subscription: subscription, event: "order.created", payload: { id: 1 }, status: :delivered,
        created_at: Time.current - latency, delivered_at: Time.current
      )
    end

    it "does not touch the cache when overview_cache_ttl is nil" do
      deliver(2)
      described_class.new.average_latency

      expect(cache.exist?(described_class::LATENCY_CACHE_KEY)).to be(false)
    end

    it "serves cached figures within the TTL" do
      RailsWebhookOutbox.config.overview_cache_ttl = 30.seconds
      deliver(2)
      expect(described_class.new.average_latency).to be_within(0.01).of(2)

      deliver(8)
      expect(described_class.new.average_latency).to be_within(0.01).of(2)
    end

    it "recomputes once the TTL has expired" do
      RailsWebhookOutbox.config.overview_cache_ttl = 30.seconds
      deliver(2)
      described_class.new.average_latency
      deliver(8)

      travel 31.seconds do
        expect(described_class.new.average_latency).to be_within(0.5).of(5)
      end
    end

    it "queries once for both figures" do
      deliver(2)
      allow(RailsWebhookOutbox::Delivery).to receive(:latency_summary).and_call_original
      instance = described_class.new
      instance.average_latency
      instance.p95_latency

      expect(RailsWebhookOutbox::Delivery).to have_received(:latency_summary).once
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
