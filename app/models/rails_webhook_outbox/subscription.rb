module RailsWebhookOutbox
  class Subscription < ApplicationRecord
    self.table_name = "webhook_outbox_subscriptions"

    URL_FORMAT = /\Ahttps?:\/\/.+/i

    before_validation :generate_secret, on: :create

    validates :url, presence: true, format: { with: URL_FORMAT, message: "must be a valid HTTP or HTTPS URL" }
    validates :secret, presence: true
    validates :events, presence: true

    scope :active, -> { where(active: true) }

    def subscribes_to?(event)
      events.include?(event.to_s)
    end

    private

    def generate_secret
      self.secret ||= SecureRandom.hex(32)
    end
  end
end
