require "net/http"
require "uri"
require "json"
require "securerandom"

module RailsWebhookOutbox
  class Sender
    def self.call(delivery)
      new(delivery).call
    end

    def initialize(delivery)
      @delivery = delivery
    end

    def call
      uri = URI.parse(@delivery.subscription.url)
      body = build_body
      request = build_request(uri, body)
      response = execute(uri, request)
      raise DeliveryError.new(response) unless response.is_a?(Net::HTTPSuccess)
      response
    end

    private

    def build_body
      JSON.generate(
        event: @delivery.event,
        delivered_at: Time.now.utc.iso8601,
        data: @delivery.payload
      )
    end

    def build_request(uri, body)
      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req["X-Webhook-Signature"] = Signature.header_value(body, @delivery.subscription.secret)
      req["X-Webhook-Event"] = @delivery.event
      req["X-Webhook-Delivery"] = SecureRandom.uuid
      req["X-Webhook-Timestamp"] = Time.now.utc.to_i.to_s
      req.body = body
      req
    end

    def execute(uri, request)
      timeout = RailsWebhookOutbox.config.request_timeout
      Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: timeout,
        read_timeout: timeout
      ) do |http|
        http.request(request)
      end
    end
  end
end
