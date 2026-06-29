class CreateWebhookOutboxDeliveries < ActiveRecord::Migration[<%= ActiveRecord::Migration.current_version %>]
  def change
    create_table :webhook_outbox_deliveries do |t|
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

    add_index :webhook_outbox_deliveries, :status
    add_index :webhook_outbox_deliveries, :event
    add_index :webhook_outbox_deliveries, [:subscription_id, :created_at]
  end
end