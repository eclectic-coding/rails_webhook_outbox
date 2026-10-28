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

  # Maximum payload size in bytes. Raises PayloadSizeError before enqueuing if exceeded.
  # Set to nil or 0 to disable.
  config.max_payload_size = 65_536

  # How long to keep delivered and failed deliveries (and their attempt history). nil keeps
  # them forever. Nothing prunes on its own: schedule RailsWebhookOutbox::PruneDeliveriesJob
  # (cron, solid_queue recurring tasks, ...) or run `rails webhook_outbox:cleanup`.
  # config.retention_period = 30.days

  # Called with the Delivery when it exhausts all retries and is marked failed, so you can
  # alert or act on it. Not called for retries or for deliveries skipped because the
  # subscription is inactive. An error raised here is logged, never re-raised.
  # config.on_dead_letter = ->(delivery) { Sentry.capture_message("Webhook failed: #{delivery.event}") }

  # Dashboard latency figures (average and p95) use at most this many of the most
  # recent deliveries from the last 24 hours, so the cost stays bounded at any volume.
  # config.latency_sample_size = 1000

  # Cache the dashboard's latency figures for this long (nil = no caching, the default).
  # Uses Rails.cache, so a shared store (Redis, Memcached, solid_cache) is needed for the
  # cache to be shared across processes. The latency tile can lag by up to this duration.
  # config.overview_cache_ttl = 30.seconds

  # Set to true in test environments to suppress HTTP calls and capture dispatched events
  # in RailsWebhookOutbox::Testing.deliveries instead of creating DB records or jobs.
  # config.test_mode = false
end