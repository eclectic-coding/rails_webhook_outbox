require "rails_webhook_outbox/version"
require "rails_webhook_outbox/configuration"
require "rails_webhook_outbox/engine"

module RailsWebhookOutbox
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    alias_method :config, :configuration

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
