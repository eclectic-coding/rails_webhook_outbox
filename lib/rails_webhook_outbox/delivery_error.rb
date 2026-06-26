module RailsWebhookOutbox
  class DeliveryError < StandardError
    attr_reader :response_code, :response_body

    def initialize(response)
      @response_code = response.code.to_i
      @response_body = response.body
      super("HTTP #{@response_code}")
    end
  end
end
