class AddSecretRotationToWebhookOutboxSubscriptions < ActiveRecord::Migration[7.2]
  def change
    add_column :webhook_outbox_subscriptions, :previous_secret, :string, if_not_exists: true
    add_column :webhook_outbox_subscriptions, :previous_secret_expires_at, :datetime, if_not_exists: true
  end
end
