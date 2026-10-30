module RailsWebhookOutbox
  class Delivery < ApplicationRecord
    include ActionView::RecordIdentifier

    self.table_name = "webhook_outbox_deliveries"

    belongs_to :subscription
    # Not `attempts`: that name is the integer counter column on this table.
    has_many :delivery_attempts, -> { order(:attempt_number) }, dependent: :delete_all

    enum :status, { pending: 0, delivered: 1, failed: 2 }

    before_validation :generate_idempotency_key, on: :create
    before_validation :stamp_payload_version, on: :create

    validates :event, presence: true
    validates :payload, presence: true
    validates :idempotency_key, presence: true

    scope :retryable, -> { pending }
    scope :delivered_within, ->(window) { delivered.where(delivered_at: window.ago..) }

    PERCENTILE_95 = 0.95
    PRUNE_BATCH_SIZE = 1000

    # Deletes delivered and failed deliveries created before `older_than` ago, in batches so
    # a large backlog never holds one long lock. Pending deliveries are never touched. The
    # attempts go with them via the foreign key's ON DELETE CASCADE. Returns the count.
    def self.prune(older_than:, batch_size: PRUNE_BATCH_SIZE)
      scope = where(status: [:delivered, :failed]).where(created_at: ...older_than.ago)
      total = 0

      loop do
        ids = scope.limit(batch_size).pluck(:id)
        break if ids.empty?

        total += where(id: ids).delete_all
        break if ids.size < batch_size
      end

      total
    end

    # Sorted end-to-end latencies (seconds) of the most recent deliveries delivered within
    # the window, capped at `config.latency_sample_size` rows so the cost stays bounded
    # however many deliveries there are. Computed in Ruby so it behaves the same on SQLite,
    # PostgreSQL, and MySQL.
    def self.latencies(window: 24.hours)
      delivered_within(window)
        .order(delivered_at: :desc)
        .limit(RailsWebhookOutbox.config.latency_sample_size)
        .pluck(:created_at, :delivered_at)
        .map { |created, delivered| delivered - created }
        .sort
    end

    def self.average_latency(window: 24.hours)
      latency_summary(window: window)[:average]
    end

    def self.p95_latency(window: 24.hours)
      latency_summary(window: window)[:p95]
    end

    # Both aggregates from a single pass over the sample; p95 is nearest-rank.
    def self.latency_summary(window: 24.hours)
      values = latencies(window: window)
      return { average: nil, p95: nil } if values.empty?

      { average: values.sum / values.size, p95: values[(PERCENTILE_95 * values.size).ceil - 1] }
    end

    # Seconds from creation to successful delivery; nil until delivered.
    def latency
      delivered_at - created_at if delivered? && delivered_at
    end

    after_update_commit :broadcast_row_update
    after_update_commit :broadcast_detail_update
    after_commit :broadcast_overview_update

    private

    def generate_idempotency_key
      self.idempotency_key ||= SecureRandom.uuid
    end

    # Fixed at creation so a retry sends the version first queued, even if the config
    # changes in between.
    def stamp_payload_version
      self.payload_version ||= RailsWebhookOutbox.config.payload_version_for(event)
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
