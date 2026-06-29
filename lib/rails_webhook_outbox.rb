require "rails_webhook_outbox/version"
require "rails_webhook_outbox/configuration"
require "rails_webhook_outbox/signature"
require "rails_webhook_outbox/delivery_error"
require "rails_webhook_outbox/payload_size_error"
require "rails_webhook_outbox/testing"
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

    def validate_event!(event)
      registered = config.events
      return if registered.empty?
      return if registered.include?(event.to_s)

      raise ArgumentError, "Unknown event #{event.inspect}. Registered events: #{registered.join(", ")}"
    end

    def validate_payload_size!(payload)
      max = config.max_payload_size
      return unless max && max > 0

      size = JSON.generate(payload).bytesize
      raise PayloadSizeError.new(size, max) if size > max
    end

    def dispatch(event, payload)
      validate_event!(event)
      validate_payload_size!(payload)

      if config.test_mode
        Testing.deliveries << { event: event.to_s, payload: payload }
        return
      end

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
