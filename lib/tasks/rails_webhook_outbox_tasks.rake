namespace :webhook_outbox do
  desc "Re-enqueue failed deliveries for retry"
  task retry_failed: :environment do
    deliveries = RailsWebhookOutbox::Delivery.failed
    count = deliveries.count

    if count.zero?
      puts "No failed deliveries to retry"
    else
      deliveries.find_each do |delivery|
        delivery.update!(status: :pending, next_retry_at: nil)
        RailsWebhookOutbox::DeliveryJob.perform_later(delivery)
      end
      puts "Re-enqueued #{count} failed #{"delivery".pluralize(count)} for retry"
    end
  end

  desc "List all webhook subscriptions"
  task list_subscriptions: :environment do
    subscriptions = RailsWebhookOutbox::Subscription.order(:id)

    if subscriptions.none?
      puts "No subscriptions found"
    else
      subscriptions.find_each do |subscription|
        puts format(
          "#%d [%s] %s events=%s failures=%d",
          subscription.id,
          subscription.active? ? "active" : "inactive",
          subscription.url,
          subscription.events.join(","),
          subscription.consecutive_failures
        )
      end
    end
  end

  desc "Delete delivered and failed deliveries older than the given number of days"
  task :cleanup, [:days] => :environment do |_task, args|
    days = args[:days].to_i

    if days <= 0
      puts "Usage: rake webhook_outbox:cleanup[days] (days must be a positive integer)"
    else
      scope = RailsWebhookOutbox::Delivery.where(status: [:delivered, :failed]).where(created_at: ...days.days.ago)
      count = scope.count
      scope.delete_all
      puts "Deleted #{count} #{"delivery".pluralize(count)} older than #{days} #{"day".pluralize(days)}"
    end
  end
end
