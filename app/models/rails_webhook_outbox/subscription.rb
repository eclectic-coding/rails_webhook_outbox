module RailsWebhookOutbox
  class Subscription < ApplicationRecord
    self.table_name = "webhook_outbox_subscriptions"

    URL_FORMAT = /\Ahttps?:\/\/.+/i

    attribute :active, :boolean, default: true

    before_validation :generate_secret, on: :create

    validates :url, presence: true, format: { with: URL_FORMAT, message: "must be a valid HTTP or HTTPS URL" }
    validates :secret, presence: true
    validates :events, presence: true

    scope :active, -> { where(active: true) }

    def subscribes_to?(event)
      events.include?(event.to_s)
    end

    def rotate_secret!(grace_period: RailsWebhookOutbox.config.secret_rotation_grace_period, force: false)
      raise SecretRotationError if previous_secret_active? && !force

      update!(
        previous_secret: secret,
        previous_secret_expires_at: Time.current + grace_period,
        secret: generate_secret_value
      )
    end

    def previous_secret_active?
      previous_secret.present? && previous_secret_expires_at.present? && previous_secret_expires_at.future?
    end

    def signing_secrets
      previous_secret_active? ? [secret, previous_secret] : [secret]
    end

    private

    def generate_secret
      self.secret ||= generate_secret_value
    end

    def generate_secret_value
      SecureRandom.hex(32)
    end
  end
end
