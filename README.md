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

## Manual Dispatch

Dispatch webhooks outside of model callbacks:

```ruby
RailsWebhookOutbox.dispatch("payment.completed", {
  id: payment.id,
  amount: payment.amount,
  currency: payment.currency
})
```

## Development

```bash
$ bundle install
$ bundle exec rspec
$ bin/rubocop
```

## Contributing

Bug reports and pull requests are welcome on [GitHub](https://github.com/eclectic-coding/rails_webhook_outbox).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).