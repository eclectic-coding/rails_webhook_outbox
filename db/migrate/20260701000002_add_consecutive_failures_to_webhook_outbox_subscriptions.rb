class AddConsecutiveFailuresToWebhookOutboxSubscriptions < ActiveRecord::Migration[7.2]
  def change
    add_column :webhook_outbox_subscriptions, :consecutive_failures, :integer, null: false, default: 0
  end
end
