require "rails_helper"

RSpec.describe RailsWebhookOutbox::Configuration do
  subject(:config) { described_class.new }

  describe "defaults" do
    it "sets events to an empty array" do
      expect(config.events).to eq([])
    end

    it "sets signing_algorithm to :sha256" do
      expect(config.signing_algorithm).to eq(:sha256)
    end

    it "sets signing_header to X-Webhook-Signature" do
      expect(config.signing_header).to eq("X-Webhook-Signature")
    end

    it "sets max_retries to 8" do
      expect(config.max_retries).to eq(8)
    end

    it "sets retry_backoff to :exponential" do
      expect(config.retry_backoff).to eq(:exponential)
    end

    it "sets request_timeout to 5" do
      expect(config.request_timeout).to eq(5)
    end

    it "sets delivery_job_queue to :webhooks" do
      expect(config.delivery_job_queue).to eq(:webhooks)
    end

    it "sets max_payload_size to 65_536" do
      expect(config.max_payload_size).to eq(65_536)
    end

    it "sets test_mode to false" do
      expect(config.test_mode).to be false
    end

    it "sets secret_rotation_grace_period to 24 hours" do
      expect(config.secret_rotation_grace_period).to eq(24.hours)
    end

    it "sets circuit_breaker_threshold to 10" do
      expect(config.circuit_breaker_threshold).to eq(10)
    end

    it "sets latency_sample_size to 1000" do
      expect(config.latency_sample_size).to eq(1000)
    end

    it "disables the overview cache" do
      expect(config.overview_cache_ttl).to be_nil
    end

    it "sets on_dead_letter to nil" do
      expect(config.on_dead_letter).to be_nil
    end
  end

  describe "#on_dead_letter=" do
    it "accepts a lambda" do
      hook = ->(delivery) { delivery }
      config.on_dead_letter = hook
      expect(config.on_dead_letter).to eq(hook)
    end

    it "accepts any object that responds to call" do
      hook = Class.new { def call(_delivery) = nil }.new
      config.on_dead_letter = hook
      expect(config.on_dead_letter).to eq(hook)
    end

    it "accepts nil to clear the hook" do
      config.on_dead_letter = ->(_delivery) {}
      config.on_dead_letter = nil
      expect(config.on_dead_letter).to be_nil
    end

    it "raises on an object that is not callable" do
      expect { config.on_dead_letter = "notify_ops" }
        .to raise_error(ArgumentError, /on_dead_letter must be nil or respond to #call/)
    end
  end

  describe "#latency_sample_size=" do
    it "accepts a positive integer" do
      config.latency_sample_size = 50
      expect(config.latency_sample_size).to eq(50)
    end

    [0, -1, 1.5, nil, "10"].each do |value|
      it "raises on #{value.inspect}" do
        expect { config.latency_sample_size = value }
          .to raise_error(ArgumentError, /latency_sample_size must be a positive integer/)
      end
    end
  end

  describe "#overview_cache_ttl=" do
    it "accepts a positive duration" do
      config.overview_cache_ttl = 30.seconds
      expect(config.overview_cache_ttl).to eq(30.seconds)
    end

    it "accepts nil to disable caching" do
      config.overview_cache_ttl = 30.seconds
      config.overview_cache_ttl = nil
      expect(config.overview_cache_ttl).to be_nil
    end

    [0, -5, "30"].each do |value|
      it "raises on #{value.inspect}" do
        expect { config.overview_cache_ttl = value }
          .to raise_error(ArgumentError, /overview_cache_ttl must be nil or a positive duration/)
      end
    end
  end

  describe "#signing_algorithm=" do
    it "accepts valid algorithms" do
      %i[sha256 sha384 sha512].each do |algo|
        config.signing_algorithm = algo
        expect(config.signing_algorithm).to eq(algo)
      end
    end

    it "converts strings to symbols" do
      config.signing_algorithm = "sha512"
      expect(config.signing_algorithm).to eq(:sha512)
    end

    it "raises on invalid algorithm" do
      expect { config.signing_algorithm = :md5 }.to raise_error(ArgumentError, /Unknown signing algorithm: md5/)
    end
  end

  describe "#retry_backoff=" do
    it "accepts valid strategies" do
      %i[exponential linear].each do |strategy|
        config.retry_backoff = strategy
        expect(config.retry_backoff).to eq(strategy)
      end
    end

    it "converts strings to symbols" do
      config.retry_backoff = "linear"
      expect(config.retry_backoff).to eq(:linear)
    end

    it "raises on invalid strategy" do
      expect { config.retry_backoff = :constant }.to raise_error(ArgumentError, /Unknown retry backoff strategy: constant/)
    end
  end

  describe "#secret_rotation_grace_period=" do
    it "accepts a positive duration" do
      config.secret_rotation_grace_period = 48.hours
      expect(config.secret_rotation_grace_period).to eq(48.hours)
    end

    it "accepts a positive number of seconds" do
      config.secret_rotation_grace_period = 3600
      expect(config.secret_rotation_grace_period).to eq(3600)
    end

    it "raises on a negative duration" do
      expect { config.secret_rotation_grace_period = -1.hour }
        .to raise_error(ArgumentError, /secret_rotation_grace_period must be a positive duration/)
    end

    it "raises on zero" do
      expect { config.secret_rotation_grace_period = 0 }
        .to raise_error(ArgumentError, /secret_rotation_grace_period must be a positive duration/)
    end

    it "raises on a non-numeric value" do
      expect { config.secret_rotation_grace_period = "1 day" }
        .to raise_error(ArgumentError, /secret_rotation_grace_period must be a positive duration/)
    end
  end

  describe "writable attributes" do
    it "allows setting events" do
      config.events = %w[order.created order.updated]
      expect(config.events).to eq(%w[order.created order.updated])
    end

    it "allows setting signing_header" do
      config.signing_header = "X-Custom-Signature"
      expect(config.signing_header).to eq("X-Custom-Signature")
    end

    it "allows setting max_retries" do
      config.max_retries = 5
      expect(config.max_retries).to eq(5)
    end

    it "allows setting request_timeout" do
      config.request_timeout = 10
      expect(config.request_timeout).to eq(10)
    end

    it "allows setting delivery_job_queue" do
      config.delivery_job_queue = :critical
      expect(config.delivery_job_queue).to eq(:critical)
    end

    it "allows setting circuit_breaker_threshold" do
      config.circuit_breaker_threshold = 5
      expect(config.circuit_breaker_threshold).to eq(5)
    end

    it "allows disabling circuit_breaker_threshold with nil" do
      config.circuit_breaker_threshold = nil
      expect(config.circuit_breaker_threshold).to be_nil
    end
  end
end