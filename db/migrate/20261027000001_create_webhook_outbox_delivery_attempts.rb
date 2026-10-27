class CreateWebhookOutboxDeliveryAttempts < ActiveRecord::Migration[7.2]
  def change
    create_table :webhook_outbox_delivery_attempts, if_not_exists: true do |t|
      t.references :delivery, null: false, index: false,
        foreign_key: { to_table: :webhook_outbox_deliveries, on_delete: :cascade }
      t.integer :attempt_number, null: false
      t.integer :outcome, null: false
      t.integer :response_code
      t.text :response_body
      t.integer :duration_ms
      t.datetime :created_at, null: false
    end

    add_index :webhook_outbox_delivery_attempts, [:delivery_id, :attempt_number], if_not_exists: true
  end
end
