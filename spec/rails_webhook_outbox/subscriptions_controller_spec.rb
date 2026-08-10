require "rails_helper"

RSpec.describe "RailsWebhookOutbox::Subscriptions", type: :request do
  let(:subscription) do
    RailsWebhookOutbox::Subscription.create!(
      url: "https://example.com/webhooks",
      events: ["order.created"],
      active: true
    )
  end

  before { RailsWebhookOutbox.config.dashboard_enabled = true }
  after  { RailsWebhookOutbox.reset_configuration! }

  describe "GET /rails_webhook_outbox/subscriptions" do
    it "returns 200 HTML with no subscriptions" do
      get "/rails_webhook_outbox/subscriptions"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No subscriptions yet")
    end

    it "lists existing subscriptions" do
      subscription
      get "/rails_webhook_outbox/subscriptions"
      expect(response.body).to include("example.com/webhooks")
    end

    it "returns 403 when the dashboard is disabled" do
      RailsWebhookOutbox.config.dashboard_enabled = false
      get "/rails_webhook_outbox/subscriptions"
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /rails_webhook_outbox/subscriptions/:id" do
    it "returns 200 HTML" do
      get "/rails_webhook_outbox/subscriptions/#{subscription.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("example.com/webhooks")
    end

    it "shows the masked secret alongside the full value for client-side reveal" do
      get "/rails_webhook_outbox/subscriptions/#{subscription.id}"
      expect(response.body).to include("••••••••#{subscription.secret.last(4)}")
      expect(response.body).to include(subscription.secret)
    end
  end

  describe "GET /rails_webhook_outbox/subscriptions/new" do
    it "returns 200 HTML" do
      get "/rails_webhook_outbox/subscriptions/new"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /rails_webhook_outbox/subscriptions" do
    it "creates a subscription with checkbox-style array events" do
      expect do
        post "/rails_webhook_outbox/subscriptions", params: {
          subscription: { url: "https://new.example.com/hooks", events: ["order.created", ""] }
        }
      end.to change(RailsWebhookOutbox::Subscription, :count).by(1)

      expect(response).to redirect_to(%r{/rails_webhook_outbox/subscriptions/\d+})
      expect(RailsWebhookOutbox::Subscription.last.events).to eq(["order.created"])
    end

    it "creates a subscription with comma-separated string events" do
      post "/rails_webhook_outbox/subscriptions", params: {
        subscription: { url: "https://new.example.com/hooks", events: "order.created, order.updated" }
      }

      expect(RailsWebhookOutbox::Subscription.last.events).to eq(["order.created", "order.updated"])
    end

    it "re-renders the form with a 422 when invalid" do
      expect do
        post "/rails_webhook_outbox/subscriptions", params: { subscription: { url: "", events: ["order.created"] } }
      end.not_to change(RailsWebhookOutbox::Subscription, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("can&#39;t be blank")
    end
  end

  describe "GET /rails_webhook_outbox/subscriptions/:id/edit" do
    it "returns 200 HTML" do
      get "/rails_webhook_outbox/subscriptions/#{subscription.id}/edit"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /rails_webhook_outbox/subscriptions/:id" do
    it "updates the subscription" do
      patch "/rails_webhook_outbox/subscriptions/#{subscription.id}", params: {
        subscription: { url: "https://updated.example.com/hooks", events: ["order.updated"] }
      }

      expect(response).to redirect_to("/rails_webhook_outbox/subscriptions/#{subscription.id}")
      expect(subscription.reload.url).to eq("https://updated.example.com/hooks")
    end

    it "toggles active without touching events" do
      patch "/rails_webhook_outbox/subscriptions/#{subscription.id}", params: {
        subscription: { active: false }
      }

      expect(subscription.reload).not_to be_active
      expect(subscription.events).to eq(["order.created"])
    end

    it "re-renders the form with a 422 when invalid" do
      patch "/rails_webhook_outbox/subscriptions/#{subscription.id}", params: {
        subscription: { url: "" }
      }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /rails_webhook_outbox/subscriptions/:id/rotate_secret" do
    it "rotates the secret and redirects" do
      old_secret = subscription.secret
      patch "/rails_webhook_outbox/subscriptions/#{subscription.id}/rotate_secret"

      expect(response).to redirect_to("/rails_webhook_outbox/subscriptions/#{subscription.id}")
      expect(subscription.reload.secret).not_to eq(old_secret)
    end

    it "redirects with a rotation_error flag when rotation is already in progress" do
      subscription.rotate_secret!(grace_period: 1.hour)

      patch "/rails_webhook_outbox/subscriptions/#{subscription.id}/rotate_secret"

      expect(response).to redirect_to(%r{/rails_webhook_outbox/subscriptions/#{subscription.id}\?rotation_error=true})
    end
  end
end
