module RailsWebhookOutbox
  module Testing
    class << self
      def deliveries
        @deliveries ||= []
      end

      def clear_deliveries!
        @deliveries = []
      end
    end
  end
end
