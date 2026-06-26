require "openssl"

module RailsWebhookOutbox
  module Signature
    def self.sign(payload, secret, algorithm)
      OpenSSL::HMAC.hexdigest(algorithm.to_s.upcase, secret, payload)
    end

    def self.header_value(payload, secret)
      algorithm = RailsWebhookOutbox.config.signing_algorithm
      "#{algorithm}=#{sign(payload, secret, algorithm)}"
    end
  end
end
