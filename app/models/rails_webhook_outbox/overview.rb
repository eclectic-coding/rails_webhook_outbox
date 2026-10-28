module RailsWebhookOutbox
  # Read model behind the dashboard overview page. Shared by OverviewController
  # and the Turbo Stream broadcasts so the page and its live updates can't drift.
  class Overview
    STREAM = "rails_webhook_outbox_overview".freeze
    STATS_TARGET = "rwo-overview-stats".freeze
    FAILURES_TARGET = "rwo-overview-failures".freeze
    RECENT_FAILURES_LIMIT = 10
    LATENCY_WINDOW = 24.hours
    LATENCY_CACHE_KEY = "rails_webhook_outbox/overview/latency".freeze

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

    def recent_failures
      Delivery.failed.includes(:subscription).order(created_at: :desc).limit(RECENT_FAILURES_LIMIT)
    end

    private

    # Cached across requests and broadcasts only when `config.overview_cache_ttl` is set.
    def latency_summary
      @latency_summary ||= if (ttl = RailsWebhookOutbox.config.overview_cache_ttl)
        Rails.cache.fetch(LATENCY_CACHE_KEY, expires_in: ttl) { Delivery.latency_summary(window: LATENCY_WINDOW) }
      else
        Delivery.latency_summary(window: LATENCY_WINDOW)
      end
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
