class CreateWebhookOutboxSubscriptions < ActiveRecord::Migration[7.2]
  def change
    create_table :webhook_outbox_subscriptions, if_not_exists: true do |t|
      t.string :url, null: false
      t.string :secret, null: false
      t.json :events, null: false, default: []
      t.boolean :active, null: false, default: true
      t.string :description
      t.json :metadata, default: {}
      t.timestamps
    end
  end
end
