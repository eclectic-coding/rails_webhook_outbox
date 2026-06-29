module RailsWebhookOutbox
  class PayloadSizeError < StandardError
    def initialize(size, max)
      super("Payload too large: #{size} bytes exceeds the #{max}-byte limit")
    end
  end
end
