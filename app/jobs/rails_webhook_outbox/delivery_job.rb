module RailsWebhookOutbox
  class DeliveryJob < ApplicationJob
    queue_as { RailsWebhookOutbox.config.delivery_job_queue }
    retry_on RailsWebhookOutbox::DeliveryError, wait: :polynomially_longer, attempts: :unlimited

    def perform(delivery)
      if RailsWebhookOutbox.config.test_mode
        delivery.update!(status: :delivered, attempts: delivery.attempts + 1, delivered_at: Time.current)
        notify("webhook.delivered.rails_webhook_outbox", delivery, 0)
        return
      end

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = Sender.call(delivery)
      duration_ms = elapsed_ms(start)
      delivery.update!(
        status: :delivered,
        response_code: response.code.to_i,
        response_body: response.body.truncate(1000),
        delivered_at: Time.current,
        attempts: delivery.attempts + 1
      )
      notify("webhook.delivered.rails_webhook_outbox", delivery, duration_ms)
    rescue DeliveryError => e
      duration_ms = elapsed_ms(start)
      max_retries = RailsWebhookOutbox.config.max_retries
      final = executions >= max_retries
      delivery.update!(
        response_code: e.response_code,
        response_body: e.response_body&.truncate(1000),
        attempts: delivery.attempts + 1,
        status: final ? :failed : :pending,
        next_retry_at: final ? nil : Time.current + ((executions**4) + 2).seconds
      )
      notify("webhook.failed.rails_webhook_outbox", delivery, duration_ms) if final
      raise unless final
    end

    private

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
  end
end
