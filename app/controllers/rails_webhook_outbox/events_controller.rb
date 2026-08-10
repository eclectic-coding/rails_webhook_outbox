module RailsWebhookOutbox
  class EventsController < BaseController
    def index
      @events = RailsWebhookOutbox.config.events.map do |event|
        {
          name: event,
          subscriber_count: Subscription.active.select { |s| s.subscribes_to?(event) }.size,
          example: Delivery.where(event: event).order(created_at: :desc).first&.payload
        }
      end
    end
  end
end
