module RailsWebhookOutbox
  class Delivery < ApplicationRecord
    include ActionView::RecordIdentifier

    self.table_name = "webhook_outbox_deliveries"

    belongs_to :subscription
    # Not `attempts`: that name is the integer counter column on this table.
    has_many :delivery_attempts, -> { order(:attempt_number) }, dependent: :delete_all

    enum :status, { pending: 0, delivered: 1, failed: 2 }

    before_validation :generate_idempotency_key, on: :create

    validates :event, presence: true
    validates :payload, presence: true
    validates :idempotency_key, presence: true

    scope :retryable, -> { pending }

    after_update_commit :broadcast_row_update
    after_update_commit :broadcast_detail_update
    after_commit :broadcast_overview_update

    private

    def generate_idempotency_key
      self.idempotency_key ||= SecureRandom.uuid
    end

    def broadcast_row_update
      broadcast_replace_to "rails_webhook_outbox_deliveries", html: render_partial("rails_webhook_outbox/deliveries/row")
    end

    def broadcast_detail_update
      broadcast_replace_to self, target: dom_id(self, :detail), html: render_partial("rails_webhook_outbox/deliveries/detail")
    end

    # Rendered through the engine's own controller: Turbo's default (the host app's
    # ApplicationController) renders blank in an API-only host and has no access to
    # the engine's route helpers.
    def render_partial(partial)
      BaseController.render(partial: partial, locals: { delivery: self }, formats: [:html])
    end

    def broadcast_overview_update
      Overview.broadcast_stats
      Overview.broadcast_recent_failures
    end
  end
end
