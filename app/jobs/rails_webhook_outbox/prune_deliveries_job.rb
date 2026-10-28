module RailsWebhookOutbox
  # Deletes finished deliveries older than config.retention_period. Scheduler-agnostic: the
  # host app runs it from cron, solid_queue recurring tasks, or whatever it already uses.
  class PruneDeliveriesJob < ApplicationJob
    queue_as { RailsWebhookOutbox.config.delivery_job_queue }

    def perform
      retention = RailsWebhookOutbox.config.retention_period
      return if retention.nil?

      count = Delivery.prune(older_than: retention)
      Rails.logger.info { "[RailsWebhookOutbox] pruned deliveries=#{count} older_than=#{retention.inspect}" }
    end
  end
end
