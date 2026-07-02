require "rails_helper"
require "rake"

RSpec.describe "webhook_outbox rake tasks" do
  include ActiveJob::TestHelper

  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("webhook_outbox:retry_failed")
  end

  let(:subscription) do
    RailsWebhookOutbox::Subscription.create!(
      url: "https://example.com/webhooks",
      events: ["order.created"]
    )
  end

  def invoke(task_name, *args)
    original = $stdout
    $stdout = StringIO.new
    Rake::Task[task_name].invoke(*args)
    $stdout.string
  ensure
    Rake::Task[task_name].reenable
    $stdout = original
  end

  describe "webhook_outbox:retry_failed" do
    it "reports when there are no failed deliveries" do
      out = invoke("webhook_outbox:retry_failed")
      expect(out).to include("No failed deliveries to retry")
    end

    it "re-enqueues failed deliveries and resets them to pending" do
      delivery = RailsWebhookOutbox::Delivery.create!(subscription: subscription, event: "order.created", payload: { id: 1 })
      delivery.update!(status: :failed)

      expect { invoke("webhook_outbox:retry_failed") }.to have_enqueued_job(RailsWebhookOutbox::DeliveryJob).with(delivery)

      expect(delivery.reload).to be_pending
      expect(delivery.next_retry_at).to be_nil
    end

    it "pluralizes the summary correctly for a single delivery" do
      delivery = RailsWebhookOutbox::Delivery.create!(subscription: subscription, event: "order.created", payload: { id: 1 })
      delivery.update!(status: :failed)

      out = invoke("webhook_outbox:retry_failed")
      expect(out).to include("Re-enqueued 1 failed delivery for retry")
    end

    it "pluralizes the summary correctly for multiple deliveries" do
      2.times do
        d = RailsWebhookOutbox::Delivery.create!(subscription: subscription, event: "order.created", payload: { id: 1 })
        d.update!(status: :failed)
      end

      out = invoke("webhook_outbox:retry_failed")
      expect(out).to include("Re-enqueued 2 failed deliveries for retry")
    end
  end

  describe "webhook_outbox:list_subscriptions" do
    it "reports when there are no subscriptions" do
      out = invoke("webhook_outbox:list_subscriptions")
      expect(out).to include("No subscriptions found")
    end

    it "lists active and inactive subscriptions" do
      active = subscription
      inactive = RailsWebhookOutbox::Subscription.create!(
        url: "https://example.com/other",
        events: ["order.cancelled"],
        active: false
      )

      out = invoke("webhook_outbox:list_subscriptions")
      expect(out).to include("##{active.id} [active] https://example.com/webhooks events=order.created failures=0")
      expect(out).to include("##{inactive.id} [inactive] https://example.com/other events=order.cancelled failures=0")
    end
  end

  describe "webhook_outbox:cleanup" do
    it "prints usage when no days argument is given" do
      out = invoke("webhook_outbox:cleanup")
      expect(out).to include("Usage: rake webhook_outbox:cleanup[days]")
    end

    it "prints usage when days is not a positive integer" do
      out = invoke("webhook_outbox:cleanup", "0")
      expect(out).to include("Usage: rake webhook_outbox:cleanup[days]")
    end

    it "deletes delivered and failed deliveries older than the given number of days" do
      old_delivered = RailsWebhookOutbox::Delivery.create!(subscription: subscription, event: "order.created", payload: { id: 1 })
      old_delivered.update!(status: :delivered)
      old_delivered.update_column(:created_at, 10.days.ago)

      old_failed = RailsWebhookOutbox::Delivery.create!(subscription: subscription, event: "order.created", payload: { id: 2 })
      old_failed.update!(status: :failed)
      old_failed.update_column(:created_at, 10.days.ago)

      recent = RailsWebhookOutbox::Delivery.create!(subscription: subscription, event: "order.created", payload: { id: 3 })
      recent.update!(status: :delivered)

      pending = RailsWebhookOutbox::Delivery.create!(subscription: subscription, event: "order.created", payload: { id: 4 })
      pending.update_column(:created_at, 10.days.ago)

      out = invoke("webhook_outbox:cleanup", "7")

      expect(out).to include("Deleted 2 deliveries older than 7 days")
      expect(RailsWebhookOutbox::Delivery.exists?(old_delivered.id)).to be false
      expect(RailsWebhookOutbox::Delivery.exists?(old_failed.id)).to be false
      expect(RailsWebhookOutbox::Delivery.exists?(recent.id)).to be true
      expect(RailsWebhookOutbox::Delivery.exists?(pending.id)).to be true
    end

    it "pluralizes the summary correctly for a single day and delivery" do
      old_delivered = RailsWebhookOutbox::Delivery.create!(subscription: subscription, event: "order.created", payload: { id: 1 })
      old_delivered.update!(status: :delivered)
      old_delivered.update_column(:created_at, 2.days.ago)

      out = invoke("webhook_outbox:cleanup", "1")
      expect(out).to include("Deleted 1 delivery older than 1 day")
    end
  end
end