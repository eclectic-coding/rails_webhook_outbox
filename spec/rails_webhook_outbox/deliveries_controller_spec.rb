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

  describe "GET /rails_webhook_outbox/deliveries.csv" do
    def csv_lines
      response.body.lines
    end

    it "downloads a CSV with a header row" do
      get "/rails_webhook_outbox/deliveries.csv"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/csv")
      expect(response.headers["Content-Disposition"]).to match(/\Aattachment; filename="webhook-deliveries-\d{8}-\d{6}\.csv"\z/)
      expect(csv_lines.first).to start_with("id,event,subscription_url")
    end

    it "does not let proxies buffer or cache the stream" do
      get "/rails_webhook_outbox/deliveries.csv"

      expect(response.headers["Cache-Control"]).to eq("no-cache")
      expect(response.headers["X-Accel-Buffering"]).to eq("no")
    end

    it "includes every delivery when unfiltered" do
      delivery
      RailsWebhookOutbox::Delivery.create!(subscription: subscription, event: "order.updated", payload: { id: 2 })

      get "/rails_webhook_outbox/deliveries.csv"

      expect(csv_lines.size).to eq(3)
    end

    it "applies the same status, event, and date filters as the list" do
      delivery.update!(status: :failed)
      RailsWebhookOutbox::Delivery.create!(subscription: subscription, event: "order.updated", payload: { id: 2 })
      old = RailsWebhookOutbox::Delivery.create!(subscription: subscription, event: "order.created", payload: { id: 3 }, status: :failed)
      old.update_column(:created_at, 10.days.ago)

      get "/rails_webhook_outbox/deliveries.csv", params: { status: "failed", event: "order.created", from: 2.days.ago.to_date.to_s }

      expect(csv_lines.size).to eq(2)
      expect(csv_lines.last).to start_with("#{delivery.id},")
    end

    it "honours the upper date bound" do
      delivery
      old = RailsWebhookOutbox::Delivery.create!(subscription: subscription, event: "order.created", payload: { id: 3 })
      old.update_column(:created_at, 10.days.ago)

      get "/rails_webhook_outbox/deliveries.csv", params: { to: 5.days.ago.to_date.to_s }

      expect(csv_lines.size).to eq(2)
      expect(csv_lines.last).to start_with("#{old.id},")
    end

    it "ignores unknown filter values, like the list" do
      delivery

      get "/rails_webhook_outbox/deliveries.csv", params: { status: "bogus", event: "nope", from: "not-a-date" }

      expect(csv_lines.size).to eq(2)
    end

    it "returns only the header when nothing matches" do
      get "/rails_webhook_outbox/deliveries.csv"

      expect(csv_lines.size).to eq(1)
    end

    it "is gated by dashboard_enabled" do
      RailsWebhookOutbox.config.dashboard_enabled = false

      get "/rails_webhook_outbox/deliveries.csv"

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "export link on the deliveries page" do
    it "links to the CSV carrying the current filters but not the page" do
      get "/rails_webhook_outbox/deliveries", params: { status: "failed", event: "order.created", page: "2" }

      link = Nokogiri::HTML(response.body).at_xpath("//a[normalize-space()='Export CSV']")
      expect(link["href"]).to start_with("/rails_webhook_outbox/deliveries.csv?")
      expect(link["href"]).to include("status=failed", "event=order.created")
      expect(link["href"]).not_to include("page=")
    end

    it "links to the unfiltered CSV when no filters are set" do
      get "/rails_webhook_outbox/deliveries"

      link = Nokogiri::HTML(response.body).at_xpath("//a[normalize-space()='Export CSV']")
      expect(link["href"]).to eq("/rails_webhook_outbox/deliveries.csv")
    end
  end

  describe "GET /rails_webhook_outbox/deliveries/:id" do
    it "returns 200 HTML" do
      get "/rails_webhook_outbox/deliveries/#{delivery.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(CGI.escapeHTML(JSON.pretty_generate(delivery.payload)))
    end

    it "shows the latency of a delivered delivery" do
      delivery.update!(status: :delivered, delivered_at: delivery.created_at + 2)
      get "/rails_webhook_outbox/deliveries/#{delivery.id}"
      expect(response.body).to include("Latency", "2.0 s")
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

    describe "timeline" do
      it "always shows when the delivery was queued" do
        get "/rails_webhook_outbox/deliveries/#{delivery.id}"
        expect(response.body).to include("Timeline", "Queued", delivery.created_at.strftime("%Y-%m-%d %H:%M:%S"))
      end

      it "lists each attempt in order with its outcome, response code, and duration" do
        delivery.delivery_attempts.create!(attempt_number: 1, outcome: :failed, response_code: 503, duration_ms: 182)
        delivery.delivery_attempts.create!(attempt_number: 2, outcome: :delivered, response_code: 200, duration_ms: 45)
        get "/rails_webhook_outbox/deliveries/#{delivery.id}"

        body = response.body
        expect(body).to include("Attempt 1", "HTTP 503", "182 ms", "Attempt 2", "HTTP 200", "45 ms")
        expect(body.index("Attempt 1")).to be < body.index("Attempt 2")
        expect(body).to include("rwo-timeline-item--failed", "rwo-timeline-item--delivered")
      end

      it "shows an attempt's response body, escaped" do
        delivery.delivery_attempts.create!(attempt_number: 1, outcome: :failed, response_code: 500, response_body: "<b>boom</b>")
        get "/rails_webhook_outbox/deliveries/#{delivery.id}"

        expect(response.body).to include("Response body", "&lt;b&gt;boom&lt;/b&gt;")
        expect(response.body).not_to include("<b>boom</b>")
      end

      it "shows a dash for a missing response code and omits a missing duration" do
        delivery.delivery_attempts.create!(attempt_number: 1, outcome: :failed)
        get "/rails_webhook_outbox/deliveries/#{delivery.id}"

        expect(response.body).to include("HTTP —")
        expect(response.body).not_to include(" ms")
        expect(response.body).not_to include("Response body")
      end

      it "shows the scheduled retry for a pending delivery" do
        delivery.update!(next_retry_at: Time.utc(2026, 11, 1, 12, 30, 0))
        get "/rails_webhook_outbox/deliveries/#{delivery.id}"

        expect(response.body).to include("Retry scheduled", "2026-11-01 12:30:00")
      end

      it "does not show a scheduled retry once the delivery has failed" do
        delivery.update!(status: :failed, next_retry_at: Time.utc(2026, 11, 1, 12, 30, 0))
        get "/rails_webhook_outbox/deliveries/#{delivery.id}"

        expect(response.body).not_to include("Retry scheduled")
      end

      it "does not show a scheduled retry for a pending delivery without a retry time" do
        get "/rails_webhook_outbox/deliveries/#{delivery.id}"
        expect(response.body).not_to include("Retry scheduled")
      end

      it "explains missing history for a delivery attempted before attempts were recorded" do
        delivery.update!(status: :delivered, attempts: 2)
        get "/rails_webhook_outbox/deliveries/#{delivery.id}"

        expect(response.body).to include("Attempt history is recorded from version 0.4.0")
      end

      it "omits the missing-history note when attempts are recorded or none were made" do
        get "/rails_webhook_outbox/deliveries/#{delivery.id}"
        expect(response.body).not_to include("Attempt history is recorded")

        delivery.update!(attempts: 1)
        delivery.delivery_attempts.create!(attempt_number: 1, outcome: :delivered, response_code: 200)
        get "/rails_webhook_outbox/deliveries/#{delivery.id}"
        expect(response.body).not_to include("Attempt history is recorded")
      end
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
