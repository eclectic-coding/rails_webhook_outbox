# RailsWebhookOutbox

[![CI](https://github.com/eclectic-coding/rails_webhook_outbox/actions/workflows/main.yml/badge.svg)](https://github.com/eclectic-coding/rails_webhook_outbox/actions/workflows/main.yml)
[![Gem Version](https://img.shields.io/gem/v/rails_webhook_outbox)](https://rubygems.org/gems/rails_webhook_outbox)
[![Gem Downloads](https://img.shields.io/gem/dt/rails_webhook_outbox)](https://rubygems.org/gems/rails_webhook_outbox)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.3-red)](https://www.ruby-lang.org)
[![Rails](https://img.shields.io/badge/rails-%3E%3D%208.1-red)](https://rubyonrails.org)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Codecov](https://codecov.io/gh/eclectic-coding/rails_webhook_outbox/graph/badge.svg)](https://codecov.io/gh/eclectic-coding/rails_webhook_outbox)

A Rails engine for sending outgoing webhooks with HMAC signing, ActiveJob-based retry, delivery logging, and a mountable dashboard.

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
- [Development](#development)
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
end
```

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

The job uses polynomial (exponentially-growing) wait intervals between retries. On each failed attempt it updates the delivery record before re-raising so progress is always persisted:

| Execution | Outcome | Delivery status |
|-----------|---------|-----------------|
| 1–(n-1) | non-2xx response | `pending` — will retry |
| n (`max_retries`) | non-2xx response | `failed` — no further retry |
| any | 2xx response | `delivered` |

Every attempt (success or failure) increments `delivery.attempts` and stores the `response_code` and `response_body`. Successful deliveries also set `delivered_at`.

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

Include the `Dispatchable` concern in your models:

```ruby
class Order < ApplicationRecord
  include RailsWebhookOutbox::Dispatchable

  dispatches_webhook "order.created", on: :create
  dispatches_webhook "order.updated", on: :update
  dispatches_webhook "order.cancelled", on: :update,
    if: -> { cancelled_at_previously_changed? }
end
```

Customize the payload by defining a `webhook_payload` method:

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

Dispatch webhooks outside of model callbacks:

```ruby
RailsWebhookOutbox.dispatch("payment.completed", {
  id: payment.id,
  amount: payment.amount,
  currency: payment.currency
})
```

[Back to top](#table-of-contents)

## Development

```bash
$ bundle install
$ bundle exec rspec
$ bin/rubocop
```

[Back to top](#table-of-contents)

## Contributing

Bug reports and pull requests are welcome on [GitHub](https://github.com/eclectic-coding/rails_webhook_outbox).

[Back to top](#table-of-contents)

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

[Back to top](#table-of-contents)
