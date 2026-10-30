module RailsWebhookOutbox
  class Configuration
    SIGNING_ALGORITHMS = %i[sha256 sha384 sha512].freeze
    RETRY_BACKOFF_STRATEGIES = %i[exponential linear].freeze

    attr_accessor :events, :signing_algorithm, :signing_header,
                  :max_retries, :retry_backoff, :request_timeout,
                  :delivery_job_queue, :max_payload_size, :test_mode,
                  :secret_rotation_grace_period, :circuit_breaker_threshold,
                  :dashboard_enabled, :latency_sample_size, :overview_cache_ttl,
                  :on_dead_letter, :retention_period, :payload_versions, :default_payload_version

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
      @circuit_breaker_threshold = 10
      @dashboard_enabled = Rails.env.development?
      @latency_sample_size = 1000
      @overview_cache_ttl = nil
      @on_dead_letter = nil
      @retention_period = nil
      @payload_versions = {}
      @default_payload_version = 1
    end

    # The payload version for an event: its entry in payload_versions, else the default.
    def payload_version_for(event)
      payload_versions.fetch(event.to_s, default_payload_version)
    end

    def default_payload_version=(value)
      unless value.is_a?(Integer) && value.positive?
        raise ArgumentError, "default_payload_version must be a positive integer"
      end

      @default_payload_version = value
    end

    # Keys may be strings or symbols; they are stored as strings to match event names.
    def payload_versions=(value)
      unless value.is_a?(Hash) && value.values.all? { |v| v.is_a?(Integer) && v.positive? }
        raise ArgumentError, "payload_versions must be a hash of event name => positive integer version"
      end

      @payload_versions = value.transform_keys(&:to_s)
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

    def retention_period=(value)
      unless value.nil? || (value.is_a?(ActiveSupport::Duration) && value.positive?)
        raise ArgumentError, "retention_period must be nil or a positive duration, e.g. 30.days"
      end

      @retention_period = value
    end

    def on_dead_letter=(value)
      unless value.nil? || value.respond_to?(:call)
        raise ArgumentError, "on_dead_letter must be nil or respond to #call"
      end

      @on_dead_letter = value
    end

    def latency_sample_size=(value)
      unless value.is_a?(Integer) && value.positive?
        raise ArgumentError, "latency_sample_size must be a positive integer"
      end

      @latency_sample_size = value
    end

    def overview_cache_ttl=(value)
      unless value.nil? || (value.is_a?(Numeric) && value.positive?)
        raise ArgumentError, "overview_cache_ttl must be nil or a positive duration"
      end

      @overview_cache_ttl = value
    end
  end
end
