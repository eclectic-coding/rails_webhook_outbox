RailsWebhookOutbox.configure do |config|
  # Events that subscribers can register for.
  config.events = %w[order.created order.updated]

  # HMAC algorithm for signing payloads. Options: :sha256, :sha384, :sha512
  config.signing_algorithm = :sha256

  # HTTP header that carries the HMAC signature.
  config.signing_header = "X-Webhook-Signature"

  # Maximum delivery attempts before a delivery is marked failed.
  config.max_retries = 8

  # Retry delay strategy. Options: :exponential, :linear
  config.retry_backoff = :exponential

  # HTTP timeout in seconds for each delivery attempt.
  config.request_timeout = 5

  # ActiveJob queue for delivery jobs.
  config.delivery_job_queue = :webhooks
end