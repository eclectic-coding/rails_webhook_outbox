module RailsWebhookOutbox
  class Configuration
    SIGNING_ALGORITHMS = %i[sha256 sha384 sha512].freeze
    RETRY_BACKOFF_STRATEGIES = %i[exponential linear].freeze

    attr_accessor :events, :signing_algorithm, :signing_header,
                  :max_retries, :retry_backoff, :request_timeout,
                  :delivery_job_queue, :max_payload_size, :test_mode,
                  :secret_rotation_grace_period

    def initialize
      @events = []
      @signing_algorithm = :sha256
      @signing_header = "X-Webhook-Signature"
      @max_retries = 8
      @retry_backoff = :exponential
      @request_timeout = 5
      @delivery_job_queue = :webhooks
      @max_payload_size = 65_536
      @test_mode = false
      @secret_rotation_grace_period = 24.hours
    end

    def signing_algorithm=(value)
      value = value.to_sym
      unless SIGNING_ALGORITHMS.include?(value)
        raise ArgumentError, "Unknown signing algorithm: #{value}. Must be one of: #{SIGNING_ALGORITHMS.join(", ")}"
      end

      @signing_algorithm = value
    end

    def retry_backoff=(value)
      value = value.to_sym
      unless RETRY_BACKOFF_STRATEGIES.include?(value)
        raise ArgumentError, "Unknown retry backoff strategy: #{value}. Must be one of: #{RETRY_BACKOFF_STRATEGIES.join(", ")}"
      end

      @retry_backoff = value
    end

    def secret_rotation_grace_period=(value)
      unless value.is_a?(Numeric) && value.positive?
        raise ArgumentError, "secret_rotation_grace_period must be a positive duration"
      end

      @secret_rotation_grace_period = value
    end
  end
end
