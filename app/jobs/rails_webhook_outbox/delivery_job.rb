module RailsWebhookOutbox
  class DeliveryJob < ApplicationJob
    queue_as { RailsWebhookOutbox.config.delivery_job_queue }
    retry_on RailsWebhookOutbox::DeliveryError, wait: :polynomially_longer, attempts: :unlimited

    def perform(delivery)
      return skip_disabled_subscription(delivery) unless delivery.subscription.active?

      wait = rate_limit_wait(delivery.subscription)
      return defer_for_rate_limit(delivery, wait) if wait

      if RailsWebhookOutbox.config.test_mode
        record_attempt(delivery, outcome: :delivered, duration_ms: 0)
        delivery.update!(status: :delivered, attempts: delivery.attempts + 1, delivered_at: Time.current)
        delivery.subscription.record_delivery_success!
        notify("webhook.delivered.rails_webhook_outbox", delivery, 0)
        return
      end

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = Sender.call(delivery)
      duration_ms = elapsed_ms(start)
      record_attempt(delivery, outcome: :delivered, response_code: response.code.to_i,
        response_body: response.body.truncate(1000), duration_ms: duration_ms)
      delivery.update!(
        status: :delivered,
        response_code: response.code.to_i,
        response_body: response.body.truncate(1000),
        delivered_at: Time.current,
        attempts: delivery.attempts + 1
      )
      delivery.subscription.record_delivery_success!
      Rails.logger.info { "[RailsWebhookOutbox] delivered event=#{delivery.event} delivery_id=#{delivery.id} subscription_id=#{delivery.subscription_id} status=#{response.code} duration=#{duration_ms}ms" }
      notify("webhook.delivered.rails_webhook_outbox", delivery, duration_ms)
    rescue DeliveryError => e
      duration_ms = elapsed_ms(start)
      max_retries = RailsWebhookOutbox.config.max_retries
      final = executions >= max_retries
      record_attempt(delivery, outcome: :failed, response_code: e.response_code,
        response_body: e.response_body&.truncate(1000), duration_ms: duration_ms)
      delivery.update!(
        response_code: e.response_code,
        response_body: e.response_body&.truncate(1000),
        attempts: delivery.attempts + 1,
        status: final ? :failed : :pending,
        next_retry_at: final ? nil : Time.current + ((executions**4) + 2).seconds
      )
      if final
        Rails.logger.error { "[RailsWebhookOutbox] failed event=#{delivery.event} delivery_id=#{delivery.id} subscription_id=#{delivery.subscription_id} status=#{e.response_code} attempts=#{delivery.attempts}" }
        notify("webhook.failed.rails_webhook_outbox", delivery, duration_ms)
        record_failure_and_notify_if_tripped(delivery)
        run_dead_letter_hook(delivery)
      else
        Rails.logger.warn { "[RailsWebhookOutbox] retry event=#{delivery.event} delivery_id=#{delivery.id} subscription_id=#{delivery.subscription_id} status=#{e.response_code} attempt=#{delivery.attempts} next_retry_at=#{delivery.next_retry_at.utc.iso8601}" }
        raise
      end
    end

    private

    def skip_disabled_subscription(delivery)
      delivery.update!(status: :failed, next_retry_at: nil)
      Rails.logger.warn { "[RailsWebhookOutbox] skipped event=#{delivery.event} delivery_id=#{delivery.id} subscription_id=#{delivery.subscription_id} reason=subscription_inactive" }
    end

    RATE_LIMIT_WINDOW = 1.minute

    # Seconds to wait before the subscription is under its limit again, or nil if it is
    # now. Counts the subscription's recorded attempts in the last minute; the wait lasts
    # until the oldest of them ages out. Under concurrent workers this is approximate: two
    # can both see room for one more.
    def rate_limit_wait(subscription)
      limit = subscription.rate_limit_per_minute
      return unless limit

      window_start = RATE_LIMIT_WINDOW.ago
      recent = DeliveryAttempt.joins(:delivery)
        .where(webhook_outbox_deliveries: { subscription_id: subscription.id })
        .where(created_at: window_start..)
      return if recent.count < limit

      oldest = recent.minimum(:created_at)
      [(oldest + RATE_LIMIT_WINDOW - Time.current).ceil, 1].max
    end

    # A deferral is not an attempt: no DeliveryAttempt, no change to `attempts` or status.
    # `executions` is rolled back too, because it counts toward max_retries and a rate
    # limited run has used none of them. retry_job (not perform_later) keeps it across runs.
    def defer_for_rate_limit(delivery, wait)
      self.executions -= 1
      Rails.logger.info { "[RailsWebhookOutbox] rate_limited event=#{delivery.event} delivery_id=#{delivery.id} subscription_id=#{delivery.subscription_id} retry_in=#{wait}s" }
      retry_job(wait: wait)
    end

    def record_attempt(delivery, outcome:, duration_ms:, response_code: nil, response_body: nil)
      delivery.delivery_attempts.create!(
        attempt_number: delivery.attempts + 1,
        outcome: outcome,
        response_code: response_code,
        response_body: response_body,
        duration_ms: duration_ms
      )
    end

    def elapsed_ms(start)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
    end

    def notify(event_name, delivery, duration_ms)
      ActiveSupport::Notifications.instrument(event_name,
        event: delivery.event,
        subscription_id: delivery.subscription_id,
        delivery_id: delivery.id,
        duration: duration_ms)
    end

    # Runs last, after the failure is persisted and the circuit breaker has been updated, so
    # host code can't interfere with either. An error in the hook is logged, never raised.
    def run_dead_letter_hook(delivery)
      RailsWebhookOutbox.config.on_dead_letter&.call(delivery)
    rescue => e
      Rails.logger.error { "[RailsWebhookOutbox] dead_letter_hook_failed event=#{delivery.event} delivery_id=#{delivery.id} error=#{e.class}: #{e.message}" }
    end

    def record_failure_and_notify_if_tripped(delivery)
      return unless delivery.subscription.record_delivery_failure!

      subscription = delivery.subscription
      Rails.logger.warn { "[RailsWebhookOutbox] circuit_breaker_tripped subscription_id=#{subscription.id} consecutive_failures=#{subscription.consecutive_failures}" }
      ActiveSupport::Notifications.instrument("webhook.circuit_breaker_tripped.rails_webhook_outbox",
        subscription_id: subscription.id,
        consecutive_failures: subscription.consecutive_failures)
    end
  end
end
