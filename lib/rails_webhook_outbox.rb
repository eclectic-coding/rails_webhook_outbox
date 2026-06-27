require "rails_webhook_outbox/version"
require "rails_webhook_outbox/configuration"
require "rails_webhook_outbox/signature"
require "rails_webhook_outbox/delivery_error"
require "rails_webhook_outbox/sender"
require "rails_webhook_outbox/dispatchable"
require "rails_webhook_outbox/engine"

module RailsWebhookOutbox
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    alias_method :config, :configuration

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end

    def dispatch(event, payload)
      Subscription.active.each do |subscription|
        next unless subscription.subscribes_to?(event)

        delivery = Delivery.create!(
          subscription: subscription,
          event: event,
          payload: payload
        )

        DeliveryJob.perform_later(delivery)
      end
    end
  end
end
