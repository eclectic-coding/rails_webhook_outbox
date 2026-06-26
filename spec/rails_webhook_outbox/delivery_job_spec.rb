require "rails_helper"

module RailsWebhookOutbox
  class Subscription < ApplicationRecord
    self.table_name = "webhook_outbox_subscriptions"
  end unless const_defined?(:Subscription)
end

RSpec.describe RailsWebhookOutbox::DeliveryJob do
  include ActiveJob::TestHelper

  let(:subscription) do
    RailsWebhookOutbox::Subscription.create!(
      url: "https://example.com/webhooks",
      secret: "test-secret-abc123",
      events: ["order.created"],
      active: true
    )
  end

  let(:delivery) do
    RailsWebhookOutbox::Delivery.create!(
      subscription: subscription,
      event: "order.created",
      payload: { id: 1 }
    )
  end

  let(:success_response) { instance_double(Net::HTTPResponse, code: "200", body: "ok") }
  let(:error_response)   { instance_double(Net::HTTPResponse, code: "503", body: "Service Unavailable") }
  let(:delivery_error)   { RailsWebhookOutbox::DeliveryError.new(error_response) }

  after { RailsWebhookOutbox.reset_configuration! }

  describe "queue" do
    it "defaults to the configured delivery_job_queue" do
      expect(described_class.new.queue_name).to eq("webhooks")
    end

    it "reflects configuration changes" do
      RailsWebhookOutbox.configure { |c| c.delivery_job_queue = :priority }
      expect(described_class.new.queue_name).to eq("priority")
    end
  end

  describe "#perform" do
    context "on a successful delivery" do
      before { allow(RailsWebhookOutbox::Sender).to receive(:call).and_return(success_response) }

      it "marks the delivery as delivered" do
        described_class.perform_now(delivery)
        expect(delivery.reload).to be_delivered
      end

      it "stores the response code as an integer" do
        described_class.perform_now(delivery)
        expect(delivery.reload.response_code).to eq(200)
      end

      it "stores the response body" do
        described_class.perform_now(delivery)
        expect(delivery.reload.response_body).to eq("ok")
      end

      it "sets delivered_at" do
        described_class.perform_now(delivery)
        expect(delivery.reload.delivered_at).to be_within(2.seconds).of(Time.current)
      end

      it "increments attempts by one" do
        described_class.perform_now(delivery)
        expect(delivery.reload.attempts).to eq(1)
      end
    end

    context "on a non-final failure (below max_retries)" do
      before do
        RailsWebhookOutbox.configure { |c| c.max_retries = 3 }
        allow(RailsWebhookOutbox::Sender).to receive(:call).and_raise(delivery_error)
      end

      it "keeps status as pending" do
        described_class.perform_now(delivery) rescue RailsWebhookOutbox::DeliveryError
        expect(delivery.reload).to be_pending
      end

      it "stores the error response code" do
        described_class.perform_now(delivery) rescue RailsWebhookOutbox::DeliveryError
        expect(delivery.reload.response_code).to eq(503)
      end

      it "stores the error response body" do
        described_class.perform_now(delivery) rescue RailsWebhookOutbox::DeliveryError
        expect(delivery.reload.response_body).to eq("Service Unavailable")
      end

      it "increments attempts by one" do
        described_class.perform_now(delivery) rescue RailsWebhookOutbox::DeliveryError
        expect(delivery.reload.attempts).to eq(1)
      end

      it "schedules a retry" do
        expect { described_class.perform_now(delivery) }
          .to have_enqueued_job(described_class)
      end
    end

    context "on the final failure (max_retries exhausted)" do
      before do
        RailsWebhookOutbox.configure { |c| c.max_retries = 1 }
        allow(RailsWebhookOutbox::Sender).to receive(:call).and_raise(delivery_error)
      end

      it "marks the delivery as failed" do
        described_class.perform_now(delivery)
        expect(delivery.reload).to be_failed
      end

      it "stores the error response code" do
        described_class.perform_now(delivery)
        expect(delivery.reload.response_code).to eq(503)
      end

      it "increments attempts by one" do
        described_class.perform_now(delivery)
        expect(delivery.reload.attempts).to eq(1)
      end

      it "does not re-raise" do
        expect { described_class.perform_now(delivery) }.not_to raise_error
      end
    end

    context "when response body is nil" do
      let(:nil_body_response) { instance_double(Net::HTTPResponse, code: "503", body: nil) }
      let(:nil_body_error)    { RailsWebhookOutbox::DeliveryError.new(nil_body_response) }

      before do
        RailsWebhookOutbox.configure { |c| c.max_retries = 1 }
        allow(RailsWebhookOutbox::Sender).to receive(:call).and_raise(nil_body_error)
      end

      it "stores nil response_body without error" do
        described_class.perform_now(delivery)
        expect(delivery.reload.response_body).to be_nil
      end
    end
  end
end