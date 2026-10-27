class AddIdempotencyKeyToWebhookOutboxDeliveries < ActiveRecord::Migration[7.2]
  def change
    add_column :webhook_outbox_deliveries, :idempotency_key, :string, if_not_exists: true
    add_index :webhook_outbox_deliveries, :idempotency_key, unique: true, if_not_exists: true
  end
end
