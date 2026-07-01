module RailsWebhookOutbox
  class SecretRotationError < StandardError
    def initialize
      super("Cannot rotate secret: the previous secret is still within its grace period. " \
            "Pass force: true to rotate anyway and immediately invalidate it.")
    end
  end
end
