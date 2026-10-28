require "rails_helper"

RSpec.describe "RailsWebhookOutbox::Stats", type: :request do
  let(:subscription) do
    RailsWebhookOutbox::Subscription.create!(url: "https://example.com/webhooks", events: ["order.created"])
  end

  before { RailsWebhookOutbox.config.dashboard_enabled = true }

  after { RailsWebhookOutbox.reset_configuration! }

  def create_delivery(status:, created_at: Time.current, **attrs)
    RailsWebhookOutbox::Delivery.create!(
      subscription: subscription, event: "order.created", payload: { id: 1 }, status: status, created_at: created_at, **attrs
    )
  end

  def stats
    JSON.parse(response.body)
  end

  describe "GET /rails_webhook_outbox/stats.json" do
    it "returns JSON with the documented shape" do
      create_delivery(status: :delivered, delivered_at: Time.current)
      create_delivery(status: :failed)
      create_delivery(status: :pending)

      get "/rails_webhook_outbox/stats.json"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      expect(stats.keys).to eq(%w[generated_at subscriptions deliveries window latency])
      expect(stats["subscriptions"]).to eq("total" => 1, "active" => 1)
      expect(stats["deliveries"]).to eq("pending" => 1, "delivered" => 1, "failed" => 1)
      expect(stats["window"]).to include("duration" => "24h", "seconds" => 86_400, "delivered" => 1, "failed" => 1, "success_rate" => 0.5)
      expect(stats["latency"].keys).to eq(%w[average_seconds p95_seconds])
    end

    it "serves the same data at /stats without an extension" do
      get "/rails_webhook_outbox/stats"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
    end

    it "reports latency for deliveries delivered in the window" do
      create_delivery(status: :delivered, created_at: Time.current - 4, delivered_at: Time.current)

      get "/rails_webhook_outbox/stats.json"

      expect(stats["latency"]["average_seconds"]).to be_within(0.5).of(4)
      expect(stats["latency"]["p95_seconds"]).to be_within(0.5).of(4)
    end

    it "reports zeros and nulls on an empty database" do
      get "/rails_webhook_outbox/stats.json"

      expect(stats["subscriptions"]).to eq("total" => 0, "active" => 0)
      expect(stats["deliveries"]).to eq("pending" => 0, "delivered" => 0, "failed" => 0)
      expect(stats["window"]).to include("delivered" => 0, "failed" => 0, "success_rate" => nil)
      expect(stats["latency"]).to eq("average_seconds" => nil, "p95_seconds" => nil)
    end

    describe "?window=" do
      before do
        create_delivery(status: :delivered)
        create_delivery(status: :failed, created_at: 3.days.ago)
      end

      it "narrows the success rate to a short window" do
        get "/rails_webhook_outbox/stats.json", params: { window: "1h" }

        expect(stats["window"]).to include("duration" => "1h", "seconds" => 3600, "success_rate" => 1.0)
      end

      it "widens it to a long one" do
        get "/rails_webhook_outbox/stats.json", params: { window: "7d" }

        expect(stats["window"]).to include("duration" => "7d", "seconds" => 604_800, "success_rate" => 0.5)
      end

      it "accepts minutes" do
        get "/rails_webhook_outbox/stats.json", params: { window: "15m" }

        expect(stats["window"]).to include("seconds" => 900)
      end

      it "accepts the largest allowed window" do
        get "/rails_webhook_outbox/stats.json", params: { window: "30d" }

        expect(response).to have_http_status(:ok)
      end

      ["abc", "24", "24x", "-1h", "1.5h", "0h", "0m", "31d", "999d", "1h; DROP", ""].each do |value|
        it "rejects #{value.inspect} with a 400 and a JSON error" do
          get "/rails_webhook_outbox/stats.json", params: { window: value }

          expect(response).to have_http_status(:bad_request)
          expect(response.media_type).to eq("application/json")
          expect(stats["error"]).to match(/window must look like/)
        end
      end
    end

    it "is gated by dashboard_enabled" do
      RailsWebhookOutbox.config.dashboard_enabled = false

      get "/rails_webhook_outbox/stats.json"

      expect(response).to have_http_status(:forbidden)
    end

    it "has no route for other formats" do
      get "/rails_webhook_outbox/stats.html"

      expect(response).to have_http_status(:not_found)
    end
  end
end

