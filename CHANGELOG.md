# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Delivery latency — `Delivery#latency` returns the seconds from creation to successful delivery (`nil` until delivered). `Delivery.average_latency` and `Delivery.p95_latency` aggregate it over a window (default: the last 24 hours). The dashboard shows the latency on the delivery detail view and the 24-hour average and p95 on the overview, which updates live. The aggregates use at most `config.latency_sample_size` (default 1000) recent deliveries so the cost stays bounded on busy apps, and the overview figures can optionally be cached with `config.overview_cache_ttl` (default `nil`, off). A new migration adds an index on `webhook_outbox_deliveries.delivered_at` so the latency query stays fast on large tables; it is not breaking, but run `bin/rails db:migrate` (see [UPGRADING.md](UPGRADING.md#upgrading-to-050)). The overview now reads its subscription counts with one query instead of two.

## [0.4.0] - 2026-10-27

### Added
- Mountable dashboard — mount `RailsWebhookOutbox::Engine` (e.g. at `/admin/webhooks`) for a browser UI, gated by `config.dashboard_enabled` (default: `true` in development only). Ships its own CSS (inlined) and JS (importmap + Turbo/Stimulus), and follows the system light/dark color scheme. Pages: overview (subscription/delivery counts, recent failures), subscriptions (list, create, edit, one-click enable/disable, masked signing secret with reveal/copy, rotate secret), deliveries (filter by status, event, and date range; paginated), delivery detail (payload, response, manual retry for failed deliveries), and registered events (subscriber counts and a recent payload example).
- Live delivery updates — `Delivery` broadcasts Turbo Stream replacements on update, so the delivery log rows and the delivery detail view refresh without a page reload; the manual retry button responds with Turbo Stream too.
- Live overview — the dashboard overview's counts and recent failures update without a reload. `Delivery` and `Subscription` broadcast Turbo Stream replacements of the stats and recent-failures partials on every create, update, and destroy. The overview data is now served by `RailsWebhookOutbox::Overview`, shared by the controller and the broadcasts.
- Delivery attempt history — `DeliveryJob` records every HTTP attempt (outcome, response code, truncated response body, duration) as a `RailsWebhookOutbox::DeliveryAttempt`, available via `Delivery#delivery_attempts`. Previously only the latest response was kept on the delivery. The install generator now also copies the migration for new apps. The foreign key cascades on delete, so `webhook_outbox:cleanup` removes attempts along with their deliveries.
- Delivery timeline — the dashboard's delivery detail view now shows a timeline: when the delivery was queued, each recorded attempt (outcome, HTTP status, duration, and an expandable response body), and the scheduled retry for a pending delivery. It updates live along with the rest of the detail view. Deliveries attempted before 0.4.0 have no attempt history and show a note saying so.
- `UPGRADING.md` — per-version upgrade notes, shipped with the gem, starting with 0.4.0.

### Changed
- **BREAKING:** a new database table, `webhook_outbox_delivery_attempts`, is required. `DeliveryJob` writes to it on every attempt, so an app that runs 0.4.0 code without the migration will send webhooks but fail to record them (the delivery is left unmarked and the job raises `ActiveRecord::StatementInvalid`). Run `bin/rails db:migrate` before deploying; see [UPGRADING.md](UPGRADING.md#upgrading-to-040).

### Fixed
- Fresh installs failed on `rails db:migrate` with `ActiveRecord::DuplicateMigrationNameError` — the install generator copied migrations that the engine also adds to the host app's migration paths. The generator now only creates the initializer; the engine supplies the migrations. Apps whose generator-copied migrations are already in `db/migrate` need a one-time cleanup; see [UPGRADING.md](UPGRADING.md#if-you-ran-the-install-generator-on-an-earlier-version).
- Live delivery updates rendered blank in API-only host apps — the delivery row and detail Turbo Stream broadcasts are now rendered through the engine's own controller instead of the host's `ApplicationController`, so they carry real content and can resolve the engine's route helpers.

## [0.3.0] - 2026-07-02

### Added
- Rake tasks — `webhook_outbox:retry_failed` re-enqueues failed deliveries as `DeliveryJob`s (resetting them to `pending`); `webhook_outbox:list_subscriptions` prints each subscription's status, events, and consecutive failure count; `webhook_outbox:cleanup[days]` deletes `delivered`/`failed` deliveries older than the given number of days.
- Circuit breaker — `Subscription` tracks `consecutive_failures`, incremented each time a delivery permanently fails (all retries exhausted) and reset to zero on success. Once `consecutive_failures` reaches `config.circuit_breaker_threshold` (default 10; `nil` or `0` disables), the subscription is automatically set `active: false` and `webhook.circuit_breaker_tripped.rails_webhook_outbox` is published with `subscription_id` and `consecutive_failures`. `DeliveryJob` now checks `subscription.active?` before every attempt, so deliveries already in flight are skipped (not retried further) once their subscription is disabled — by the breaker or manually. Reactivating a subscription resets `consecutive_failures` to zero immediately, so it can't be instantly re-tripped by the next failure.
- Secret rotation — `Subscription#rotate_secret!` generates a new HMAC secret and keeps the old one valid for a configurable grace period (`config.secret_rotation_grace_period`, default 24 hours). While the previous secret is active, outgoing requests are signed with both secrets so subscribers can transition without downtime; `X-Webhook-Signature` carries a comma-separated list of signatures. `RailsWebhookOutbox::Signature.header_value` now also accepts an array of secrets. Rotating again before the previous secret's grace period ends raises `RailsWebhookOutbox::SecretRotationError` unless `force: true` is passed.
- `ActiveSupport::Notifications` instrumentation — `DeliveryJob` publishes `webhook.delivered.rails_webhook_outbox` on successful delivery and `webhook.failed.rails_webhook_outbox` on permanent failure (all retries exhausted). Each event payload includes `event`, `subscription_id`, `delivery_id`, and `duration` (integer milliseconds). Non-final failures publish no notification.
- Structured logging — `Sender` logs an `info`-level attempt line (event, idempotency key, URL) before each HTTP call. `DeliveryJob` logs `info` on success (with response code and duration), `warn` on retryable failure (with attempt count and `next_retry_at`), and `error` on permanent failure. All lines are prefixed `[RailsWebhookOutbox]` in key=value format.

## [0.2.0] - 2026-06-29

### Added
- Event validation — `RailsWebhookOutbox.validate_event!(event)` raises `ArgumentError` when the event is not in `config.events`; called automatically by `dispatch` and `Dispatchable` callbacks. Validation is skipped when `config.events` is empty for backward compatibility.
- Idempotency key — `Delivery` records now store an auto-generated UUID in `idempotency_key`; the `X-Webhook-Delivery` header uses this stored value across all retry attempts so subscribers can deduplicate incoming webhooks.
- Payload size limit — `config.max_payload_size` (default 65 536 bytes) raises `RailsWebhookOutbox::PayloadSizeError` before enqueuing if the JSON-serialised payload exceeds the limit. Set to `nil` or `0` to disable.
- `next_retry_at` — `DeliveryJob` now sets `next_retry_at` on each retryable failure using the polynomial backoff formula (`executions⁴ + 2` seconds); cleared to `nil` when all retries are exhausted.
- Test mode and RSpec matchers — `config.test_mode = true` suppresses HTTP calls and DB writes; dispatched events are captured in `RailsWebhookOutbox::Testing.deliveries` for assertions. Load `require "rails_webhook_outbox/rspec_matchers"` to get the `dispatch_webhook` matcher with optional `with_payload` chain.

## [0.1.0] - 2026-06-29

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

[Unreleased]: https://github.com/eclectic-coding/rails_webhook_outbox/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/eclectic-coding/rails_webhook_outbox/releases/tag/v0.4.0
[0.3.0]: https://github.com/eclectic-coding/rails_webhook_outbox/releases/tag/v0.3.0
[0.2.0]: https://github.com/eclectic-coding/rails_webhook_outbox/releases/tag/v0.2.0
[0.1.0]: https://github.com/eclectic-coding/rails_webhook_outbox/releases/tag/v0.1.0
