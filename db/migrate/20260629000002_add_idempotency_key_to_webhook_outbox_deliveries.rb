class AddIdempotencyKeyToWebhookOutboxDeliveries < ActiveRecord::Migration[7.2]
  def change
    add_column :webhook_outbox_deliveries, :idempotency_key, :string
    add_index :webhook_outbox_deliveries, :idempotency_key, unique: true
  end
end
