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

    it "shows an unlimited rate limit by default" do
      get "/rails_webhook_outbox/subscriptions/#{subscription.id}"
      expect(response.body).to match(%r{Rate Limit</div>\s*<div[^>]*>Unlimited</div>})
    end

    it "shows the configured rate limit" do
      subscription.update!(rate_limit_per_minute: 30)
      get "/rails_webhook_outbox/subscriptions/#{subscription.id}"
      expect(response.body).to match(%r{Rate Limit</div>\s*<div[^>]*>30 / minute</div>})
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

    it "creates a subscription with a rate limit" do
      post "/rails_webhook_outbox/subscriptions", params: {
        subscription: { url: "https://new.example.com/hooks", events: ["order.created"], rate_limit_per_minute: "10" }
      }

      expect(RailsWebhookOutbox::Subscription.last.rate_limit_per_minute).to eq(10)
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

      expect(response).to have_http_status(422)
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

      expect(response).to have_http_status(422)
    end

    it "sets the rate limit" do
      patch "/rails_webhook_outbox/subscriptions/#{subscription.id}", params: {
        subscription: { rate_limit_per_minute: "30" }
      }

      expect(subscription.reload.rate_limit_per_minute).to eq(30)
    end

    it "clears the rate limit when the field is blank" do
      subscription.update!(rate_limit_per_minute: 30)
      patch "/rails_webhook_outbox/subscriptions/#{subscription.id}", params: {
        subscription: { rate_limit_per_minute: "" }
      }

      expect(subscription.reload.rate_limit_per_minute).to be_nil
    end

    it "re-renders the form with a 422 for a rate limit of zero" do
      patch "/rails_webhook_outbox/subscriptions/#{subscription.id}", params: {
        subscription: { rate_limit_per_minute: "0" }
      }

      expect(response).to have_http_status(422)
      expect(response.body).to include("must be greater than 0")
    end
  end

  # Browsers submit button_to forms as POST with a hidden _method field. The dummy app is
  # API-only (no Rack::MethodOverride), like many hosts, so the engine must handle this itself.
  describe "form submissions using _method override" do
    it "updates a subscription from the edit form" do
      post "/rails_webhook_outbox/subscriptions/#{subscription.id}",
        params: { _method: "patch", subscription: { url: "https://updated.example.com/hooks" } }

      expect(response).to redirect_to("/rails_webhook_outbox/subscriptions/#{subscription.id}")
      expect(subscription.reload.url).to eq("https://updated.example.com/hooks")
    end

    it "rotates the secret from the show page's button" do
      expect {
        post "/rails_webhook_outbox/subscriptions/#{subscription.id}/rotate_secret", params: { _method: "patch" }
      }.to change { subscription.reload.secret }
    end

    it "submits the rendered Disable button's form successfully" do
      subscription
      get "/rails_webhook_outbox/subscriptions"
      form = Nokogiri::HTML(response.body).at_css("form.button_to")
      fields = form.css("input[type=hidden]").to_h { |input| [input["name"], input["value"]] }

      post form["action"], params: fields

      expect(subscription.reload).not_to be_active
    end
  end

  describe "PATCH /rails_webhook_outbox/subscriptions/:id/toggle" do
    let(:path) { "/rails_webhook_outbox/subscriptions/#{subscription.id}/toggle" }
    let(:turbo_stream_headers) { { "Accept" => "text/vnd.turbo-stream.html" } }

    it "disables the subscription and replaces just its row with a Turbo Stream" do
      patch path, params: { active: false }, headers: turbo_stream_headers

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('action="replace"', %(target="subscription_#{subscription.id}"))
      expect(response.body).to include("Disabled", "Enable")
      expect(subscription.reload).not_to be_active
    end

    it "enables a disabled subscription" do
      subscription.update!(active: false)

      patch path, params: { active: true }, headers: turbo_stream_headers

      expect(response.body).to include("Active", "Disable")
      expect(subscription.reload).to be_active
    end

    it "sets the state it was asked for rather than flipping it" do
      patch path, params: { active: true }, headers: turbo_stream_headers

      expect(subscription.reload).to be_active
    end

    it "redirects to the index, not the show page, without Turbo" do
      patch path, params: { active: false }

      expect(response).to redirect_to("/rails_webhook_outbox/subscriptions")
      expect(subscription.reload).not_to be_active
    end

    it "returns 400 when the target state is missing" do
      patch path

      expect(response).to have_http_status(:bad_request)
      expect(subscription.reload).to be_active
    end

    it "is gated by dashboard_enabled" do
      RailsWebhookOutbox.config.dashboard_enabled = false

      patch path, params: { active: false }

      expect(response).to have_http_status(:forbidden)
      expect(subscription.reload).to be_active
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
