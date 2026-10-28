module RailsWebhookOutbox
  # Read model behind the dashboard overview page. Shared by OverviewController
  # and the Turbo Stream broadcasts so the page and its live updates can't drift.
  class Overview
    STREAM = "rails_webhook_outbox_overview".freeze
    STATS_TARGET = "rwo-overview-stats".freeze
    FAILURES_TARGET = "rwo-overview-failures".freeze
    RECENT_FAILURES_LIMIT = 10
    DEFAULT_WINDOW = 24.hours
    CACHE_KEY_PREFIX = "rails_webhook_outbox/overview".freeze

    def self.broadcast_stats
      broadcast_replace(STATS_TARGET, "rails_webhook_outbox/overview/stats")
    end

    def self.broadcast_recent_failures
      broadcast_replace(FAILURES_TARGET, "rails_webhook_outbox/overview/recent_failures")
    end

    # Rendered through the engine's own controller: the host app's ApplicationController
    # (which Turbo defaults to) may be API-only and renders partials blank, and it has no
    # access to the engine's route helpers.
    def self.broadcast_replace(target, partial)
      html = BaseController.render(partial: partial, locals: { overview: new }, formats: [:html])
      Turbo::StreamsChannel.broadcast_replace_to(STREAM, target: target, html: html)
    end
    private_class_method :broadcast_replace

    # The window scopes the success rate and latency figures. The counts are all-time.
    def initialize(window: DEFAULT_WINDOW)
      @window = window
    end

    def subscription_count
      subscription_counts.values.sum
    end

    def active_subscription_count
      subscription_counts.fetch(true, 0)
    end

    def delivery_count(status)
      delivery_counts.fetch(status.to_s, 0)
    end

    def average_latency
      latency_summary[:average]
    end

    def p95_latency
      latency_summary[:p95]
    end

    # Delivered / (delivered + failed) among deliveries created in the window; pending ones
    # haven't succeeded or failed yet, so they don't count. nil when nothing has finished.
    def success_rate
      finished = window_outcomes[:delivered] + window_outcomes[:failed]
      (window_outcomes[:delivered].to_f / finished).round(4) if finished.positive?
    end

    def recent_failures
      Delivery.failed.includes(:subscription).order(created_at: :desc).limit(RECENT_FAILURES_LIMIT)
    end

    # The payload behind GET /stats.json, built here so the endpoint and the dashboard read
    # the same figures.
    def to_stats(window_label:)
      {
        generated_at: Time.current.utc.iso8601,
        subscriptions: { total: subscription_count, active: active_subscription_count },
        deliveries: Delivery.statuses.keys.index_with { |status| delivery_count(status) },
        window: {
          duration: window_label,
          seconds: @window.to_i,
          delivered: window_outcomes[:delivered],
          failed: window_outcomes[:failed],
          success_rate: success_rate
        },
        latency: { average_seconds: average_latency, p95_seconds: p95_latency }
      }
    end

    private

    def latency_summary
      @latency_summary ||= cached(:latency) { Delivery.latency_summary(window: @window) }
    end

    def window_outcomes
      @window_outcomes ||= cached(:outcomes) do
        counts = Delivery.where(status: [:delivered, :failed]).where(created_at: @window.ago..).group(:status).count
        { delivered: counts.fetch("delivered", 0), failed: counts.fetch("failed", 0) }
      end
    end

    # Cached across requests and broadcasts only when `config.overview_cache_ttl` is set.
    # The window is part of the key, so different windows don't share a value.
    def cached(name, &block)
      ttl = RailsWebhookOutbox.config.overview_cache_ttl
      return yield unless ttl

      Rails.cache.fetch("#{CACHE_KEY_PREFIX}/#{name}/#{@window.to_i}", expires_in: ttl, &block)
    end

    # One query for both the total and the active count.
    def subscription_counts
      @subscription_counts ||= Subscription.group(:active).count
    end

    def delivery_counts
      @delivery_counts ||= Delivery.group(:status).count
    end
  end
end
