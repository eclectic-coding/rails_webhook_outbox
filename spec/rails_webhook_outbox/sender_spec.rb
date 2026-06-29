require "rails_helper"

RSpec.describe RailsWebhookOutbox::Sender do
  let(:url)             { "https://example.com/webhooks" }
  let(:secret)          { "test-secret" }
  let(:idempotency_key) { "550e8400-e29b-41d4-a716-446655440000" }
  let(:subscription)    { double("Subscription", url: url, secret: secret) }
  let(:delivery) do
    double("Delivery", subscription: subscription, event: "order.created",
      payload: { "id" => 1 }, idempotency_key: idempotency_key)
  end

  after { RailsWebhookOutbox.reset_configuration! }

  describe ".call" do
    context "on a successful response" do
      before { stub_request(:post, url).to_return(status: 200, body: "ok") }

      it "POSTs to the subscription URL" do
        described_class.call(delivery)
        expect(WebMock).to have_requested(:post, url)
      end

      it "sets Content-Type to application/json" do
        described_class.call(delivery)
        expect(WebMock).to have_requested(:post, url)
          .with(headers: { "Content-Type" => "application/json" })
      end

      it "sets X-Webhook-Event to the event name" do
        described_class.call(delivery)
        expect(WebMock).to have_requested(:post, url)
          .with(headers: { "X-Webhook-Event" => "order.created" })
      end

      it "sets X-Webhook-Delivery to the delivery's idempotency key" do
        described_class.call(delivery)
        expect(WebMock).to have_requested(:post, url)
          .with(headers: { "X-Webhook-Delivery" => idempotency_key })
      end

      it "sets X-Webhook-Timestamp to a Unix timestamp" do
        described_class.call(delivery)
        expect(WebMock).to have_requested(:post, url)
          .with(headers: { "X-Webhook-Timestamp" => /\A\d+\z/ })
      end

      it "sets X-Webhook-Signature using the subscription secret" do
        described_class.call(delivery)
        expect(WebMock).to have_requested(:post, url)
          .with(headers: { "X-Webhook-Signature" => /\Asha256=/ })
      end

      it "sends a JSON body with event, delivered_at, and data keys" do
        described_class.call(delivery)
        expect(WebMock).to have_requested(:post, url).with { |req|
          body = JSON.parse(req.body)
          body["event"] == "order.created" &&
            body["delivered_at"].is_a?(String) &&
            body["data"] == { "id" => 1 }
        }
      end

      it "returns the HTTP response" do
        response = described_class.call(delivery)
        expect(response.code).to eq("200")
      end
    end

    context "on a non-2xx response" do
      it "raises DeliveryError for a 4xx response" do
        stub_request(:post, url).to_return(status: 422, body: "Unprocessable")
        expect { described_class.call(delivery) }
          .to raise_error(RailsWebhookOutbox::DeliveryError)
      end

      it "raises DeliveryError for a 5xx response" do
        stub_request(:post, url).to_return(status: 500, body: "Server Error")
        expect { described_class.call(delivery) }
          .to raise_error(RailsWebhookOutbox::DeliveryError)
      end

      it "exposes the response code on the error" do
        stub_request(:post, url).to_return(status: 503, body: "Unavailable")
        error = nil
        begin
          described_class.call(delivery)
        rescue RailsWebhookOutbox::DeliveryError => e
          error = e
        end
        expect(error.response_code).to eq(503)
        expect(error.response_body).to eq("Unavailable")
      end
    end

    context "with a configured request timeout" do
      it "uses the configured timeout" do
        RailsWebhookOutbox.configure { |c| c.request_timeout = 10 }
        stub_request(:post, url).to_return(status: 200)
        expect(Net::HTTP).to receive(:start).with(
          "example.com", 443,
          hash_including(open_timeout: 10, read_timeout: 10)
        ).and_call_original
        described_class.call(delivery)
      end
    end
  end
end
