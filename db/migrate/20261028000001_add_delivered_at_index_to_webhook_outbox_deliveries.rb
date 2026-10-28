class AddDeliveredAtIndexToWebhookOutboxDeliveries < ActiveRecord::Migration[7.2]
  def change
    add_index :webhook_outbox_deliveries, :delivered_at, if_not_exists: true
  end
end
