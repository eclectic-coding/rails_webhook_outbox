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
  t.json    :events,      null: false, default: [] # ["order.created", "order.updated"]
  t.boolean :active,      null: false, default: true
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

Non-final failures (retryable errors) publish no notification.

**Payload keys** (same for both events):

| Key | Type | Description |
|-----|------|-------------|
| `event` | String | Webhook event name, e.g. `"order.created"` |
| `subscription_id` | Integer | ID of the `Subscription` record |
| `delivery_id` | Integer | ID of the `Delivery` record |
| `duration` | Integer | Elapsed time in milliseconds for the HTTP attempt (0 in test_mode) |

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
```

## HMAC signing verification (for subscribers)

```ruby
expected = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", secret, raw_body)
Rack::Utils.secure_compare(expected, request.headers["X-Webhook-Signature"])
```

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
