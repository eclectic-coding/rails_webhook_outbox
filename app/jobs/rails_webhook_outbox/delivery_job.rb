module RailsWebhookOutbox
  class DeliveryJob < ApplicationJob
    queue_as { RailsWebhookOutbox.config.delivery_job_queue }
    retry_on RailsWebhookOutbox::DeliveryError, wait: :polynomially_longer, attempts: :unlimited

    def perform(delivery)
      if RailsWebhookOutbox.config.test_mode
        delivery.update!(status: :delivered, attempts: delivery.attempts + 1, delivered_at: Time.current)
        return
      end

      response = Sender.call(delivery)
      delivery.update!(
        status: :delivered,
        response_code: response.code.to_i,
        response_body: response.body.truncate(1000),
        delivered_at: Time.current,
        attempts: delivery.attempts + 1
      )
    rescue DeliveryError => e
      max_retries = RailsWebhookOutbox.config.max_retries
      final = executions >= max_retries
      delivery.update!(
        response_code: e.response_code,
        response_body: e.response_body&.truncate(1000),
        attempts: delivery.attempts + 1,
        status: final ? :failed : :pending,
        next_retry_at: final ? nil : Time.current + ((executions**4) + 2).seconds
      )
      raise unless final
    end
  end
end
