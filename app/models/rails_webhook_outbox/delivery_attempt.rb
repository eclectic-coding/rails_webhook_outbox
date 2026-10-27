module RailsWebhookOutbox
  # One HTTP attempt to deliver a webhook. Written by DeliveryJob so the dashboard
  # can show the full attempt history, not just the latest result on the Delivery.
  class DeliveryAttempt < ApplicationRecord
    self.table_name = "webhook_outbox_delivery_attempts"

    belongs_to :delivery

    enum :outcome, { delivered: 0, failed: 1 }

    validates :attempt_number, presence: true
  end
end
