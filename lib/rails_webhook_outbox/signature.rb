require "openssl"

module RailsWebhookOutbox
  module Signature
    def self.sign(payload, secret, algorithm)
      OpenSSL::HMAC.hexdigest(algorithm.to_s.upcase, secret, payload)
    end

    def self.header_value(payload, secrets)
      algorithm = RailsWebhookOutbox.config.signing_algorithm
      Array(secrets).map { |secret| "#{algorithm}=#{sign(payload, secret, algorithm)}" }.join(",")
    end
  end
end
