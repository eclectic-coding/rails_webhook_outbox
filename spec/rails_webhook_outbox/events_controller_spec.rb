require "rails_helper"

RSpec.describe "RailsWebhookOutbox::Events", type: :request do
  let(:subscription) do
    RailsWebhookOutbox::Subscription.create!(
      url: "https://example.com/webhooks",
      events: ["order.created"],
      active: true
    )
  end

  before do
    RailsWebhookOutbox.config.dashboard_enabled = true
    RailsWebhookOutbox.config.events = %w[order.created order.updated]
  end

  after { RailsWebhookOutbox.reset_configuration! }

  describe "GET /rails_webhook_outbox/events" do
    it "returns 200 HTML" do
      get "/rails_webhook_outbox/events"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("order.created")
      expect(response.body).to include("order.updated")
    end

    it "shows the subscriber count for an event" do
      subscription
      get "/rails_webhook_outbox/events"
      expect(response.body).to include("1 active subscriber")
    end

    it "shows a recent delivery payload as an example" do
      RailsWebhookOutbox::Delivery.create!(subscription: subscription, event: "order.created", payload: { id: 42 })
      get "/rails_webhook_outbox/events"
      expect(response.body).to include(CGI.escapeHTML(JSON.pretty_generate({ id: 42 })))
    end

    it "shows an empty state for events with no deliveries" do
      get "/rails_webhook_outbox/events"
      expect(response.body).to include("No deliveries yet for this event")
    end

    it "shows an empty state when no events are registered" do
      RailsWebhookOutbox.config.events = []
      get "/rails_webhook_outbox/events"
      expect(response.body).to include("No events registered")
    end
  end
end
