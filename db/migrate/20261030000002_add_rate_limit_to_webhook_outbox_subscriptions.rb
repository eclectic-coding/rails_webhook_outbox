class AddRateLimitToWebhookOutboxSubscriptions < ActiveRecord::Migration[7.2]
  def change
    add_column :webhook_outbox_subscriptions, :rate_limit_per_minute, :integer, if_not_exists: true
  end
end
