module RailsWebhookOutbox
  class OverviewController < BaseController
    def show
      @subscription_count = Subscription.count
      @active_subscription_count = Subscription.active.count
      @delivery_counts = Delivery.group(:status).count
      @recent_failures = Delivery.failed.order(created_at: :desc).limit(10)
    end
  end
end
