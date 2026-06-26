module RailsWebhookOutbox
  class Delivery < ApplicationRecord
    self.table_name = "webhook_outbox_deliveries"

    belongs_to :subscription

    enum :status, { pending: 0, delivered: 1, failed: 2 }

    validates :event, presence: true
    validates :payload, presence: true

    scope :retryable, -> { pending }
  end
end
