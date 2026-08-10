require "rails_helper"

RSpec.describe "RailsWebhookOutbox::Deliveries", type: :request do
  let(:subscription) do
    RailsWebhookOutbox::Subscription.create!(
      url: "https://example.com/webhooks",
      events: ["order.created", "order.updated"],
      active: true
    )
  end

  let(:delivery) do
    RailsWebhookOutbox::Delivery.create!(subscription: subscription, event: "order.created", payload: { id: 1 })
  end

  before do
    RailsWebhookOutbox.config.dashboard_enabled = true
    RailsWebhookOutbox.config.events = %w[order.created order.updated]
  end

  after { RailsWebhookOutbox.reset_configuration! }

  describe "GET /rails_webhook_outbox/deliveries" do
    it "returns 200 HTML with no deliveries" do
      get "/rails_webhook_outbox/deliveries"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No deliveries found")
    end

    it "lists deliveries" do
      delivery
      get "/rails_webhook_outbox/deliveries"
      expect(response.body).to include("order.created")
    end

    it "filters by a valid status" do
      delivery.update!(status: :failed)
      get "/rails_webhook_outbox/deliveries", params: { status: "failed" }
      expect(response.body).to include(delivery.event)
    end

    it "ignores an invalid status" do
      delivery
      get "/rails_webhook_outbox/deliveries", params: { status: "bogus" }
      expect(response.body).to include(delivery.event)
    end

    it "filters by a registered event" do
      delivery
      get "/rails_webhook_outbox/deliveries", params: { event: "order.created" }
      expect(response.body).to include(delivery.event)
    end

    it "ignores an unregistered event" do
      delivery
      get "/rails_webhook_outbox/deliveries", params: { event: "not.registered" }
      expect(response).to have_http_status(:ok)
    end

    it "filters by a from/to date range" do
      delivery
      get "/rails_webhook_outbox/deliveries", params: { from: 1.day.ago.to_date.to_s, to: 1.day.from_now.to_date.to_s }
      expect(response.body).to include(delivery.event)
    end

    it "ignores an unparseable date" do
      delivery
      get "/rails_webhook_outbox/deliveries", params: { from: "not-a-date" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(delivery.event)
    end

    it "accepts an explicit page number" do
      delivery
      get "/rails_webhook_outbox/deliveries", params: { page: 2 }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No deliveries found")
    end
  end

  describe "GET /rails_webhook_outbox/deliveries/:id" do
    it "returns 200 HTML" do
      get "/rails_webhook_outbox/deliveries/#{delivery.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(CGI.escapeHTML(JSON.pretty_generate(delivery.payload)))
    end

    it "shows the retry button for a failed delivery" do
      delivery.update!(status: :failed)
      get "/rails_webhook_outbox/deliveries/#{delivery.id}"
      expect(response.body).to include("Retry Delivery")
    end

    it "hides the retry button for a pending delivery" do
      get "/rails_webhook_outbox/deliveries/#{delivery.id}"
      expect(response.body).not_to include("Retry Delivery")
    end
  end

  describe "POST /rails_webhook_outbox/deliveries/:id/retry" do
    before { delivery.update!(status: :failed) }

    it "re-enqueues the delivery and redirects for HTML requests" do
      expect do
        post "/rails_webhook_outbox/deliveries/#{delivery.id}/retry"
      end.to have_enqueued_job(RailsWebhookOutbox::DeliveryJob)

      expect(response).to redirect_to("/rails_webhook_outbox/deliveries/#{delivery.id}")
      expect(delivery.reload).to be_pending
      expect(delivery.next_retry_at).to be_nil
    end

    it "responds with a turbo stream" do
      post "/rails_webhook_outbox/deliveries/#{delivery.id}/retry", headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("turbo-stream")
      expect(response.body).to include("turbo-stream")
    end
  end
end
