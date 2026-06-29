# RailsWebhookOutbox

[![CI](https://github.com/eclectic-coding/rails_webhook_outbox/actions/workflows/main.yml/badge.svg)](https://github.com/eclectic-coding/rails_webhook_outbox/actions/workflows/main.yml)
[![Gem Version](https://img.shields.io/gem/v/rails_webhook_outbox)](https://rubygems.org/gems/rails_webhook_outbox)
[![Gem Downloads](https://img.shields.io/gem/dt/rails_webhook_outbox)](https://rubygems.org/gems/rails_webhook_outbox)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.3-red)](https://www.ruby-lang.org)
[![Rails](https://img.shields.io/badge/rails-%3E%3D%207.2-red)](https://rubyonrails.org)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Codecov](https://codecov.io/gh/eclectic-coding/rails_webhook_outbox/graph/badge.svg)](https://codecov.io/gh/eclectic-coding/rails_webhook_outbox)

A Rails engine for sending outgoing webhooks with HMAC signing, ActiveJob-based retry, and delivery logging.

## Table of Contents

- [Installation](#installation)
- [Configuration](#configuration)
- [Subscriptions](#subscriptions)
- [Deliveries](#deliveries)
- [Async Delivery](#async-delivery)
- [HTTP Request Format](#http-request-format)
- [HMAC Signing](#hmac-signing)
- [Usage](#usage)
- [Manual Dispatch](#manual-dispatch)
- [Testing](#testing)
- [Development](#development)
  - [Dummy App](#dummy-app)
- [Contributing](#contributing)
- [License](#license)

## Installation

Add this line to your application's Gemfile:

```ruby
gem "rails_webhook_outbox"
```

And then execute:

```bash
$ bundle install
```

Run the install generator:

```bash
$ rails generate rails_webhook_outbox:install
$ rails db:migrate
```

## Configuration

```ruby
# config/initializers/rails_webhook_outbox.rb
RailsWebhookOutbox.configure do |config|
  config.events = %w[
    order.created
    order.updated
    user.signed_up
  ]

  config.signing_algorithm  = :sha256
  config.signing_header     = "X-Webhook-Signature"
  config.max_retries        = 8
  config.retry_backoff      = :exponential
  config.request_timeout    = 5
  config.delivery_job_queue = :webhooks
  config.max_payload_size   = 65_536  # bytes; set to nil or 0 to disable
end
```

When `config.events` is set, both `dispatch` and `Dispatchable` callbacks will raise `ArgumentError` if the event name is not in the list. Leave `config.events` empty to skip validation entirely.

If the JSON-serialised payload exceeds `config.max_payload_size` bytes, `RailsWebhookOutbox::PayloadSizeError` is raised before any `Delivery` record is created or job enqueued. The default limit is 64 KB (`65_536` bytes).

[Back to top](#table-of-contents)

## Subscriptions

A `RailsWebhookOutbox::Subscription` represents an endpoint that receives webhook events.

```ruby
sub = RailsWebhookOutbox::Subscription.create!(
  url: "https://example.com/webhooks",
  events: ["order.created", "order.updated"]
)

sub.secret          # => "a3f9..." (auto-generated 64-char hex string)
sub.active?         # => true (default)
sub.subscribes_to?("order.created")  # => true
sub.subscribes_to?("payment.failed") # => false
```

Use the `active` scope to find enabled subscriptions:

```ruby
RailsWebhookOutbox::Subscription.active
```

Disable a subscription by setting `active: false`:

```ruby
sub.update!(active: false)
```

[Back to top](#table-of-contents)

## Deliveries

A `RailsWebhookOutbox::Delivery` records each attempt to send a webhook event to a subscription endpoint.

```ruby
delivery = RailsWebhookOutbox::Delivery.create!(
  subscription: subscription,
  event: "order.created",
  payload: { id: 42, total: "99.00" }
)

delivery.pending?    # => true (default)
delivery.delivered!
delivery.delivered?  # => true
```

Filter deliveries by status:

```ruby
RailsWebhookOutbox::Delivery.retryable   # pending — awaiting delivery or retry
RailsWebhookOutbox::Delivery.delivered   # successfully delivered
RailsWebhookOutbox::Delivery.failed      # exhausted all retries
```

[Back to top](#table-of-contents)

## Async Delivery

`RailsWebhookOutbox::DeliveryJob` handles HTTP dispatch for each `Delivery` record. It is an `ActiveJob` subclass, so it works with any queue backend (Sidekiq, Solid Queue, GoodJob, etc.).

Configure the queue and retry behaviour in the initializer:

```ruby
RailsWebhookOutbox.configure do |config|
  config.delivery_job_queue = :webhooks  # default
  config.max_retries        = 8          # default
end
```

The job uses polynomial backoff (`:polynomially_longer`) between retries — wait time grows with each attempt. On each failed attempt it updates the delivery record before re-raising so progress is always persisted:

| Execution | Outcome | Delivery status |
|-----------|---------|-----------------|
| 1–(n-1) | non-2xx response | `pending` — will retry |
| n (`max_retries`) | non-2xx response | `failed` — no further retry |
| any | 2xx response | `delivered` |

Every attempt (success or failure) increments `delivery.attempts` and stores the `response_code` and `response_body`. Successful deliveries also set `delivered_at`. Retryable failures set `next_retry_at` to the estimated time of the next attempt (based on the polynomial formula `executions⁴ + 2` seconds); it is cleared to `nil` once all retries are exhausted.

Enqueue a delivery manually:

```ruby
RailsWebhookOutbox::DeliveryJob.perform_later(delivery)
```

[Back to top](#table-of-contents)

## HTTP Request Format

Each webhook delivery is an HTTP POST to the subscription URL with the following headers and body:

```
POST https://example.com/webhooks
Content-Type: application/json
X-Webhook-Signature: sha256=a1b2c3d4...
X-Webhook-Event: order.created
X-Webhook-Delivery: 550e8400-e29b-41d4-a716-446655440000
X-Webhook-Timestamp: 1719100800

{
  "event": "order.created",
  "delivered_at": "2026-06-26T10:00:00Z",
  "data": { "id": 42, "total": "99.00" }
}
```

`X-Webhook-Delivery` is the delivery's `idempotency_key` — a UUID generated once when the `Delivery` record is created and reused on every retry attempt. Subscribers can use this value to deduplicate incoming webhooks.

Non-2xx responses raise `RailsWebhookOutbox::DeliveryError`, which carries `response_code` and `response_body` for logging and retry decisions.

[Back to top](#table-of-contents)

## HMAC Signing

Every outgoing request includes an `X-Webhook-Signature` header (configurable) containing an HMAC digest of the request body:

```
X-Webhook-Signature: sha256=a1b2c3d4...
```

Subscribers can verify the signature:

```ruby
expected = RailsWebhookOutbox::Signature.header_value(raw_body, subscription.secret)
Rack::Utils.secure_compare(expected, request.headers["X-Webhook-Signature"])
```

You can also call the primitives directly:

```ruby
# Produce a hex digest with an explicit algorithm
RailsWebhookOutbox::Signature.sign(payload, secret, :sha256)
# => "a1b2c3d4..."

# Produce the full header value using the configured algorithm
RailsWebhookOutbox::Signature.header_value(payload, secret)
# => "sha256=a1b2c3d4..."
```

[Back to top](#table-of-contents)

## Usage

Include `RailsWebhookOutbox::Dispatchable` in any ActiveRecord model to automatically dispatch webhooks on lifecycle events:

```ruby
class Order < ApplicationRecord
  include RailsWebhookOutbox::Dispatchable

  dispatches_webhook "order.created", on: :create
  dispatches_webhook "order.updated", on: :update
  dispatches_webhook "order.cancelled", on: :update,
    if: -> { cancelled_at_previously_changed? }
end
```

When a callback fires, the concern finds every active `Subscription` that includes that event, creates a `Delivery` record for each one, and enqueues a `DeliveryJob`. No other wiring is required.

The `if:` option accepts a lambda that is evaluated in the context of the model instance, so any attribute or method is available.

**Payload**

By default the full record is sent as the webhook payload via `as_json`. Override `webhook_payload` to control exactly what is sent:

```ruby
class Order < ApplicationRecord
  include RailsWebhookOutbox::Dispatchable

  dispatches_webhook "order.created", on: :create

  def webhook_payload
    { id:, total: total.to_s, items: line_items.count }
  end
end
```

[Back to top](#table-of-contents)

## Manual Dispatch

Dispatch a webhook event outside of model callbacks using `RailsWebhookOutbox.dispatch`:

```ruby
RailsWebhookOutbox.dispatch("payment.completed", {
  id: payment.id,
  amount: payment.amount,
  currency: payment.currency
})
```

`dispatch` validates the event name against `config.events` (if configured), then finds every active `Subscription` that includes the given event, creates a `Delivery` record for each one, and enqueues a `DeliveryJob`. Subscriptions that are inactive or do not subscribe to the event are skipped silently.

You can also validate an event name directly without dispatching:

```ruby
RailsWebhookOutbox.validate_event!("payment.completed")
# raises ArgumentError if the event is not in config.events
```

This is the same delivery pipeline used by `Dispatchable` callbacks, so retries, HMAC signing, and delivery logging all apply.

[Back to top](#table-of-contents)

## Testing

Enable test mode in your `rails_helper.rb` to suppress HTTP calls and DB writes during specs:

```ruby
require "rails_webhook_outbox/rspec_matchers"

RailsWebhookOutbox.configure { |c| c.test_mode = true }

RSpec.configure do |config|
  config.before { RailsWebhookOutbox::Testing.clear_deliveries! }
end
```

When `test_mode` is `true`, dispatched events are captured in memory instead of creating `Delivery` records or enqueuing jobs. Use the `dispatch_webhook` matcher to assert on them:

```ruby
expect { order.save! }.to dispatch_webhook("order.created")
expect { order.save! }.to dispatch_webhook("order.created").with_payload({ id: order.id })
expect { order.save! }.not_to dispatch_webhook("order.updated")
```

Inspect captured events directly if needed:

```ruby
RailsWebhookOutbox::Testing.deliveries
# => [{ event: "order.created", payload: { "id" => 1, ... } }]
```

`DeliveryJob` also respects `test_mode` — if a job is enqueued and performed directly in a test, it marks the delivery as `delivered` without making an HTTP call.

[Back to top](#table-of-contents)

## Development

```bash
$ bundle install
$ bundle exec rspec
$ bin/rubocop
```

### Dummy App

The gem includes a full dummy Rails app at `spec/dummy/` for end-to-end testing in a running server. It has an `Order` model wired to `Dispatchable`, an `OrdersController`, and seed data.

**Setup**

From the repo root:

```bash
$ cd spec/dummy
$ bin/setup          # installs deps, runs db:prepare, then starts the server
```

Or set up without starting the server:

```bash
$ bin/rails db:create db:migrate
$ bin/rails db:schema:load:queue
$ bin/rails db:seed
```

**Start the server**

`bin/dev` runs the web server and solid_queue worker together via foreman:

```bash
$ bin/dev
```

The API is available at `http://localhost:3000`.

**Try it with curl**

Create an order (fires `order.created`):

```bash
curl -X POST http://localhost:3000/orders \
  -H "Content-Type: application/json" \
  -d '{"order": {"title": "Widget Pack", "total": "49.99", "status": "pending"}}'
```

Update an order (fires `order.updated`):

```bash
curl -X PATCH http://localhost:3000/orders/1 \
  -H "Content-Type: application/json" \
  -d '{"order": {"status": "confirmed"}}'
```

Cancel an order (fires `order.cancelled`):

```bash
curl -X PATCH http://localhost:3000/orders/1 \
  -H "Content-Type: application/json" \
  -d '{"order": {"status": "cancelled", "cancelled_at": "2026-06-29T12:00:00Z"}}'
```

The seed data creates a subscription pointing to `http://localhost:4000/webhooks`. Point it at any local receiver (e.g. a `webhook.site` URL or a local listener) by updating the subscription record directly:

```ruby
RailsWebhookOutbox::Subscription.first.update!(url: "https://webhook.site/your-id")
```

[Back to top](#table-of-contents)

## Contributing

Bug reports and pull requests are welcome on [GitHub](https://github.com/eclectic-coding/rails_webhook_outbox).

[Back to top](#table-of-contents)

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

[Back to top](#table-of-contents)
