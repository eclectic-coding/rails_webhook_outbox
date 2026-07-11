require "rails_helper"

RSpec.describe "RailsWebhookOutbox::Overview", type: :request do
  let(:subscription) do
    RailsWebhookOutbox::Subscription.create!(
      url: "https://example.com/webhooks",
      events: ["order.created"],
      active: true
    )
  end

  before { RailsWebhookOutbox.config.dashboard_enabled = true }
  after  { RailsWebhookOutbox.reset_configuration! }

  describe "GET /rails_webhook_outbox" do
    it "returns 200 HTML" do
      get "/rails_webhook_outbox"
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "returns 403 when the dashboard is disabled" do
      RailsWebhookOutbox.config.dashboard_enabled = false
      get "/rails_webhook_outbox"
      expect(response).to have_http_status(:forbidden)
    end

    context "with subscriptions and deliveries" do
      before do
        delivered = RailsWebhookOutbox::Delivery.create!(subscription: subscription, event: "order.created", payload: { id: 1 })
        delivered.update!(status: :delivered)

        failed = RailsWebhookOutbox::Delivery.create!(subscription: subscription, event: "order.created", payload: { id: 2 })
        failed.update!(status: :failed)
      end

      it "shows the recent failures" do
        get "/rails_webhook_outbox"
        expect(response.body).to include("order.created")
      end
    end

    context "with no failed deliveries" do
      it "shows an empty state" do
        get "/rails_webhook_outbox"
        expect(response.body).to include("No failed deliveries")
      end
    end
  end
end
