module RailsWebhookOutbox
  class Delivery < ApplicationRecord
    include ActionView::RecordIdentifier

    self.table_name = "webhook_outbox_deliveries"

    belongs_to :subscription

    enum :status, { pending: 0, delivered: 1, failed: 2 }

    before_validation :generate_idempotency_key, on: :create

    validates :event, presence: true
    validates :payload, presence: true
    validates :idempotency_key, presence: true

    scope :retryable, -> { pending }

    after_update_commit :broadcast_row_update
    after_update_commit :broadcast_detail_update

    private

    def generate_idempotency_key
      self.idempotency_key ||= SecureRandom.uuid
    end

    def broadcast_row_update
      broadcast_replace_to "rails_webhook_outbox_deliveries",
        partial: "rails_webhook_outbox/deliveries/row", locals: { delivery: self }
    end

    def broadcast_detail_update
      broadcast_replace_to self,
        target: dom_id(self, :detail),
        partial: "rails_webhook_outbox/deliveries/detail", locals: { delivery: self }
    end
  end
end
