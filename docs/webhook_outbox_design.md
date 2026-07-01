# rails_webhook_outbox — Design Sketch

A Rails engine for sending outgoing webhooks with HMAC signing, ActiveJob-based retry, delivery logging, and a mountable dashboard.

**Why this gem:** The Rails ecosystem has many *incoming* webhook gems (stripe_event, github_webhook) but no standalone gem for the *outgoing* side. Every SaaS eventually needs this.

## Name options

| Name | Pros | Cons |
|------|------|------|
| `webhook_outbox` | Available on RubyGems, references transactional outbox pattern | Doesn't signal "Rails engine" |
| `dispatch_hook` | Short, action-oriented | Less discoverable |
| `rails_webhook_outbox` | Discoverable, signals Rails | Longer |

## Release plan

- **v0.1.0** — Core: subscriptions, delivery log, event DSL, HMAC signing, ActiveJob retry
- **v0.2.0** — Dashboard: mountable engine with Turbo, dark mode, subscription management, delivery browser, manual retry
- **v0.3.0** — Polish: payload versioning, rate limiting, stats JSON endpoint, CSV export

## Database schema

```ruby
create_table :webhook_outbox_subscriptions do |t|
  t.string  :url,         null: false
  t.string  :secret,      null: false  # auto-generated HMAC secret
  t.string  :previous_secret               # prior secret, active during rotation grace period
  t.datetime :previous_secret_expires_at   # when previous_secret stops being accepted
  t.json    :events,      null: false, default: [] # ["order.created", "order.updated"]
  t.boolean :active,      null: false, default: true
  t.integer :consecutive_failures, null: false, default: 0  # trips the circuit breaker
  t.string  :description
  t.json    :metadata,    default: {}
  t.timestamps
end

create_table :webhook_outbox_deliveries do |t|
  t.references :subscription, null: false, foreign_key: { to_table: :webhook_outbox_subscriptions }
  t.string     :event,         null: false
  t.json       :payload,       null: false
  t.integer    :status,        null: false, default: 0  # enum: pending, delivered, failed
  t.integer    :response_code
  t.text       :response_body
  t.integer    :attempts,      null: false, default: 0
  t.datetime   :delivered_at
  t.datetime   :next_retry_at
  t.timestamps
end

add_index :webhook_outbox_deliveries, :status
add_index :webhook_outbox_deliveries, :event
add_index :webhook_outbox_deliveries, [:subscription_id, :created_at]
```

## Configuration

```ruby
# config/initializers/webhook_outbox.rb
WebhookOutbox.configure do |config|
  config.events = %w[
    order.created
    order.updated
    order.cancelled
    user.signed_up
    payment.completed
  ]

  config.signing_algorithm  = :sha256
  config.signing_header     = "X-Webhook-Signature"
  config.max_retries        = 8
  config.retry_backoff      = :exponential  # 1, 2, 4, 8, 16, 32, 64, 128 min
  config.request_timeout    = 5             # seconds
  config.delivery_job_queue = :webhooks     # ActiveJob queue name
  config.circuit_breaker_threshold = 10     # consecutive permanent failures before auto-disabling; nil/0 disables
end
```

## Model concern

```ruby
class Order < ApplicationRecord
  include WebhookOutbox::Dispatchable

  dispatches_webhook "order.created",   on: :create
  dispatches_webhook "order.updated",   on: :update
  dispatches_webhook "order.cancelled", on: :update, if: -> { cancelled_at_previously_changed? }
end
```

## Payload customization

```ruby
class Order < ApplicationRecord
  include WebhookOutbox::Dispatchable

  dispatches_webhook "order.created", on: :create

  def webhook_payload
    { id:, total: total.to_s, items: line_items.count, customer_email: customer.email }
  end
end
```

## Manual dispatch

```ruby
WebhookOutbox.dispatch("payment.completed", {
  id: payment.id,
  amount: payment.amount,
  currency: payment.currency
})
```

## HTTP request format

```
POST https://subscriber-url.com/webhooks
Content-Type: application/json
X-Webhook-Signature: sha256=a1b2c3d4...
X-Webhook-Event: order.created
X-Webhook-Delivery: uuid-here
X-Webhook-Timestamp: 1719100800

{
  "event": "order.created",
  "delivered_at": "2026-06-23T12:00:00Z",
  "data": { "id": 42, "total": "99.00", ... }
}
```

## Delivery job

```ruby
class WebhookOutbox::DeliveryJob < ApplicationJob
  queue_as { WebhookOutbox.config.delivery_job_queue }
  retry_on WebhookOutbox::DeliveryError, wait: :polynomially_longer, attempts: 8

  def perform(delivery)
    response = WebhookOutbox::Sender.call(delivery)
    delivery.update!(
      status: :delivered,
      response_code: response.code,
      response_body: response.body.truncate(1000),
      delivered_at: Time.current,
      attempts: delivery.attempts + 1
    )
  rescue WebhookOutbox::DeliveryError => e
    delivery.update!(
      response_code: e.response_code,
      response_body: e.response_body&.truncate(1000),
      attempts: delivery.attempts + 1,
      status: executions >= 8 ? :failed : :pending
    )
    raise
  end
end
```

## Instrumentation

`DeliveryJob` publishes `ActiveSupport::Notifications` events at the end of each delivery attempt.

| Event | When |
|-------|------|
| `webhook.delivered.rails_webhook_outbox` | HTTP call succeeded (2xx response) |
| `webhook.failed.rails_webhook_outbox` | All retries exhausted — permanent failure |
| `webhook.circuit_breaker_tripped.rails_webhook_outbox` | A permanent failure pushed `consecutive_failures` to `config.circuit_breaker_threshold`, auto-disabling the subscription |

Non-final failures (retryable errors) publish no notification.

**Payload keys** for `webhook.delivered` / `webhook.failed`:

| Key | Type | Description |
|-----|------|-------------|
| `event` | String | Webhook event name, e.g. `"order.created"` |
| `subscription_id` | Integer | ID of the `Subscription` record |
| `delivery_id` | Integer | ID of the `Delivery` record |
| `duration` | Integer | Elapsed time in milliseconds for the HTTP attempt (0 in test_mode) |

**Payload keys** for `webhook.circuit_breaker_tripped`:

| Key | Type | Description |
|-----|------|-------------|
| `subscription_id` | Integer | ID of the `Subscription` record that was disabled |
| `consecutive_failures` | Integer | Consecutive permanent failures at the moment the breaker tripped |

**Example subscriber:**

```ruby
ActiveSupport::Notifications.subscribe("webhook.delivered.rails_webhook_outbox") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  Rails.logger.info "[webhook] delivered #{event.payload[:event]} in #{event.payload[:duration]}ms"
end

ActiveSupport::Notifications.subscribe("webhook.failed.rails_webhook_outbox") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  Sentry.capture_message("Webhook permanently failed",
    extra: event.payload.slice(:event, :subscription_id, :delivery_id))
end

ActiveSupport::Notifications.subscribe("webhook.circuit_breaker_tripped.rails_webhook_outbox") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  Sentry.capture_message("Webhook subscription auto-disabled",
    extra: event.payload.slice(:subscription_id, :consecutive_failures))
end
```

## Logging

`Sender` and `DeliveryJob` emit structured `Rails.logger` output for every delivery lifecycle event. All lines are prefixed `[RailsWebhookOutbox]` in key=value (Logfmt) format.

| Source | Level | When | Keys |
|--------|-------|------|------|
| `Sender` | `info` | Before HTTP call | `event`, `key` (idempotency key), `url` |
| `DeliveryJob` | `info` | Successful delivery | `event`, `delivery_id`, `subscription_id`, `status`, `duration` |
| `DeliveryJob` | `warn` | Retryable failure | `event`, `delivery_id`, `subscription_id`, `status`, `attempt`, `next_retry_at` |
| `DeliveryJob` | `error` | Permanent failure | `event`, `delivery_id`, `subscription_id`, `status`, `attempts` |
| `DeliveryJob` | `warn` | Circuit breaker tripped | `subscription_id`, `consecutive_failures` |

Example output:

```
[RailsWebhookOutbox] attempt event=order.created key=550e8400-e29b-41d4-a716-446655440000 url=https://example.com/webhooks
[RailsWebhookOutbox] delivered event=order.created delivery_id=1 subscription_id=1 status=200 duration=45ms
[RailsWebhookOutbox] retry event=order.created delivery_id=1 subscription_id=1 status=503 attempt=1 next_retry_at=2026-07-01T00:00:13Z
[RailsWebhookOutbox] failed event=order.created delivery_id=1 subscription_id=1 status=503 attempts=3
[RailsWebhookOutbox] circuit_breaker_tripped subscription_id=1 consecutive_failures=10
```

## HMAC signing verification (for subscribers)

The header may contain more than one comma-separated `algorithm=digest` pair while a subscription's
secret is rotating (see below), so check each one and accept the request if any match:

```ruby
expected = OpenSSL::HMAC.hexdigest("SHA256", secret, raw_body)
signatures = request.headers["X-Webhook-Signature"].to_s.split(",")
valid = signatures.any? { |sig| Rack::Utils.secure_compare(sig, "sha256=#{expected}") }
```

## Secret rotation

`Subscription#rotate_secret!` generates a new HMAC secret while keeping the old one valid for a
configurable grace period (`config.secret_rotation_grace_period`, default 24 hours). During the
grace period, outgoing requests are signed with **both** secrets — the header carries a
comma-separated list of `algorithm=digest` pairs, one per active secret:

```
X-Webhook-Signature: sha256=<new-secret-digest>,sha256=<previous-secret-digest>
```

See the verification snippet above for how subscribers should accept a header that carries more
than one signature. This lets a subscriber update their configured secret at their own pace within
the grace window without dropping any webhook deliveries.

The schema holds only one previous secret, so rotating again while the previous one is still
active raises `RailsWebhookOutbox::SecretRotationError` rather than silently discarding it. Pass
`force: true` to rotate anyway.

## Circuit breaker

`Subscription#consecutive_failures` tracks how many deliveries in a row have permanently failed
(all retries exhausted). `DeliveryJob` calls `Subscription#record_delivery_success!` on every
successful delivery, resetting the counter to zero, and `Subscription#record_delivery_failure!` on
every permanent failure, incrementing it.

Once `consecutive_failures` reaches `config.circuit_breaker_threshold` (default 10), the
subscription is automatically set `active: false` — no further deliveries are dispatched to it
until an operator re-enables it — and `webhook.circuit_breaker_tripped.rails_webhook_outbox` is
published. Set `config.circuit_breaker_threshold` to `nil` or `0` to disable auto-disabling
entirely.

`DeliveryJob` checks `subscription.active?` before every attempt (not just at dispatch time), so
deliveries already in flight when the breaker trips are skipped — marked `failed` immediately,
without another HTTP call or retry — instead of continuing to hammer the now-disabled endpoint on
their own backoff schedule. The same check applies to a subscription an operator disables manually.

`record_delivery_failure!` is wrapped in `with_lock` so the read-increment-compare-disable sequence
is atomic per subscription row, and the increment is skipped once the subscription is already
inactive — otherwise `consecutive_failures` would climb unboundedly after tripping. Reactivating a
subscription (`active: false` → `true`) resets `consecutive_failures` to zero immediately, so a
single failure right after re-enabling doesn't instantly re-trip the breaker.

Retryable (non-final) failures do not count towards the threshold; only a delivery that has
exhausted all of `config.max_retries` counts as one consecutive failure.

## Dashboard routes

| Route | Purpose |
|-------|---------|
| `/admin/webhooks` | Overview — delivery success rate, recent failures |
| `/admin/webhooks/subscriptions` | List/create/edit/disable subscriptions |
| `/admin/webhooks/deliveries` | Filterable delivery log |
| `/admin/webhooks/deliveries/:id` | Detail — request/response, retry button |
| `/admin/webhooks/events` | Registered events, payload examples |
| `/admin/webhooks/stats.json` | Metrics endpoint for monitoring |

## Engine mount

```ruby
# Gemfile
gem "webhook_outbox"

# routes.rb
mount WebhookOutbox::Engine => "/admin/webhooks"

# terminal
rails webhook_outbox:install:migrations
rails db:migrate
```

## Gem structure

```
webhook_outbox/
├── app/
│   ├── controllers/webhook_outbox/
│   ├── jobs/webhook_outbox/
│   ├── models/webhook_outbox/
│   └── views/webhook_outbox/
├── config/routes.rb
├── db/migrate/
├── lib/
│   ├── webhook_outbox.rb
│   ├── webhook_outbox/configuration.rb
│   ├── webhook_outbox/dispatchable.rb
│   ├── webhook_outbox/sender.rb
│   ├── webhook_outbox/signature.rb
│   └── webhook_outbox/engine.rb
├── spec/
└── webhook_outbox.gemspec
```

## Engine class

```ruby
module WebhookOutbox
  class Engine < ::Rails::Engine
    isolate_namespace WebhookOutbox

    initializer "webhook_outbox.active_record" do
      ActiveSupport.on_load(:active_record) do
        include WebhookOutbox::Dispatchable
      end
    end
  end
end
```

## Competitive landscape (as of June 2026)

- `active_webhook` — abandoned (last release July 2021, 8.6K downloads)
- `bullet_train-outgoing_webhooks` — locked into Bullet Train framework
- Service-specific gems (stripe_event, github_webhook) — incoming only
- **No standalone, maintained outgoing webhook gem exists**
