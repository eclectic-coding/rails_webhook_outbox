module RailsWebhookOutbox
  module Dispatchable
    extend ActiveSupport::Concern

    included do
      class_attribute :_webhook_dispatches, instance_writer: false
      self._webhook_dispatches = []
    end

    class_methods do
      def dispatches_webhook(event, on:, **options)
        condition = options[:if]
        self._webhook_dispatches = _webhook_dispatches + [{ event: event, on: on, condition: condition }]
        send(:"after_#{on}", -> { _dispatch_webhook(event, condition) })
      end
    end

    def webhook_payload
      as_json
    end

    private

    def _dispatch_webhook(event, condition)
      return if condition && !instance_exec(&condition)

      RailsWebhookOutbox.validate_event!(event)

      payload = webhook_payload
      RailsWebhookOutbox.validate_payload_size!(payload)

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
