class CreateWebhookOutboxDeliveries < ActiveRecord::Migration[7.2]
  def change
    create_table :webhook_outbox_deliveries, if_not_exists: true do |t|
      t.references :subscription, null: false, foreign_key: { to_table: :webhook_outbox_subscriptions }
      t.string :event, null: false
      t.json :payload, null: false
      t.integer :status, null: false, default: 0
      t.integer :response_code
      t.text :response_body
      t.integer :attempts, null: false, default: 0
      t.datetime :delivered_at
      t.datetime :next_retry_at
      t.timestamps
    end

    add_index :webhook_outbox_deliveries, :status, if_not_exists: true
    add_index :webhook_outbox_deliveries, :event, if_not_exists: true
    add_index :webhook_outbox_deliveries, [:subscription_id, :created_at], if_not_exists: true
  end
end
