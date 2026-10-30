class AddPayloadVersionToWebhookOutboxDeliveries < ActiveRecord::Migration[7.2]
  def change
    add_column :webhook_outbox_deliveries, :payload_version, :integer, if_not_exists: true
  end
end