class AddSecretRotationToWebhookOutboxSubscriptions < ActiveRecord::Migration[7.2]
  def change
    add_column :webhook_outbox_subscriptions, :previous_secret, :string
    add_column :webhook_outbox_subscriptions, :previous_secret_expires_at, :datetime
  end
end
