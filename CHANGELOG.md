# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- README with full usage documentation covering installation, configuration, subscriptions, deliveries, async delivery, HTTP format, HMAC signing, `Dispatchable`, manual dispatch, and dummy app setup
- `rails generate rails_webhook_outbox:install` generator
  - Copies `create_webhook_outbox_subscriptions` and `create_webhook_outbox_deliveries` migrations to the host app with correct timestamps and the host app's Rails migration version
  - Creates `config/initializers/rails_webhook_outbox.rb` with all configuration options and inline documentation
- Dummy app built out for end-to-end development and manual testing
  - `Order` model wired to `Dispatchable` — fires `order.created`, `order.updated`, and `order.cancelled` webhooks via `dispatches_webhook` callbacks
  - `OrdersController` — API-only `create` and `update` actions with `resources :orders` routes
  - `Order` migration — `title`, `total`, `status`, `cancelled_at` columns
  - `solid_queue` gem added; configured as the development queue adapter
  - `RailsWebhookOutbox` initializer with documented configuration defaults
  - `Procfile.dev` — runs web server and solid_queue worker together via foreman
  - Seed data — sample subscription and three orders covering pending, confirmed, and cancelled states
- Engine core
  - `RailsWebhookOutbox::Dispatchable` concern — `dispatches_webhook(event, on:)` class macro registering `after_create`/`after_update` callbacks; `if:` conditional lambda support; `webhook_payload` override method (defaults to `as_json`)
  - `RailsWebhookOutbox::DeliveryJob` — ActiveJob subclass with `queue_as` from configuration, `retry_on DeliveryError` with polynomial backoff, delivery record updates on success and failure, and automatic `failed` marking after `max_retries` exhausted
  - `RailsWebhookOutbox::Sender` service — HTTP POST via `Net::HTTP` with HMAC signature, event, delivery, and timestamp headers; JSON body envelope with `event`, `delivered_at`, and `data`; configurable request timeout; raises `DeliveryError` on non-2xx responses
  - `RailsWebhookOutbox::DeliveryError` — `StandardError` subclass exposing `response_code` and `response_body` from failed HTTP responses
  - `RailsWebhookOutbox::Signature` module — `.sign(payload, secret, algorithm)` HMAC hex digest and `.header_value(payload, secret)` returning a formatted `"sha256=..."` string
- Models and database
  - `RailsWebhookOutbox::Subscription` model — URL/format and events presence validations, auto-generated HMAC secret on create, `active` scope, and `subscribes_to?(event)` query method
  - `RailsWebhookOutbox::Delivery` model — status enum (pending/delivered/failed), belongs-to subscription, event and payload validations, `retryable` / `delivered` / `failed` scopes
  - Database migrations for `webhook_outbox_subscriptions` and `webhook_outbox_deliveries` tables with indexes on status, event, and subscription+created_at
- Configuration
  - `RailsWebhookOutbox::Configuration` — DSL with defaults for events, signing algorithm, signing header, max retries, retry backoff, request timeout, and delivery job queue
  - `RailsWebhookOutbox.configure` block API, `.config` / `.configuration` accessors, and `.reset_configuration!`
  - `RailsWebhookOutbox.dispatch(event, payload)` — finds all active subscriptions matching the event, creates a `Delivery` record for each, and enqueues a `DeliveryJob`
  - Validation for `signing_algorithm` (sha256, sha384, sha512) and `retry_backoff` (exponential, linear)

### Fixed
- `spec/rails_helper.rb` — removed broken `require_relative '../config/environment'`; engine migration path now auto-appended and test DB auto-migrated

[Unreleased]: https://github.com/eclectic-coding/rails_webhook_outbox/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/eclectic-coding/rails_webhook_outbox/releases/tag/v0.1.0
