# Roadmap

> Planned features for **rails_webhook_outbox**.
> Completed items are moved to CHANGELOG.md and removed from this file.
> Shipped sections are removed automatically by `bin/release`.

## 0.1 — Core

### Milestone 1: Foundation

- `RailsWebhookOutbox::Configuration` — configuration DSL with defaults
  - `RailsWebhookOutbox.configure` block API
  - `events` — registered event names
  - `signing_algorithm` — default `:sha256`
  - `signing_header` — default `"X-Webhook-Signature"`
  - `max_retries` — default `8`
  - `retry_backoff` — default `:exponential`
  - `request_timeout` — default `5` (seconds)
  - `delivery_job_queue` — default `:webhooks`
- Database migrations
  - `webhook_outbox_subscriptions` table (url, secret, events, active, description, metadata)
  - `webhook_outbox_deliveries` table (subscription ref, event, payload, status, response_code, response_body, attempts, delivered_at, next_retry_at)
  - Indexes on deliveries (status, event, subscription+created_at)
- `RailsWebhookOutbox::Subscription` model
  - Validations (url presence/format, secret presence, events presence)
  - Auto-generate secret on create
  - `active` scope
  - `subscribes_to?(event)` query method
- `RailsWebhookOutbox::Delivery` model
  - Status enum (pending, delivered, failed)
  - Belongs-to subscription association
  - Validations (event presence, payload presence)
  - `retryable` / `failed` / `delivered` scopes

### Milestone 2: Signing and HTTP Delivery

- `RailsWebhookOutbox::Signature` module
  - `.sign(payload, secret, algorithm)` — HMAC hex digest
  - `.header_value(payload, secret)` — formatted `"sha256=abcdef..."` string
- `RailsWebhookOutbox::Sender` service
  - HTTP POST with `Net::HTTP`
  - Request headers: Content-Type, X-Webhook-Signature, X-Webhook-Event, X-Webhook-Delivery, X-Webhook-Timestamp
  - JSON body with `event`, `delivered_at`, and `data` envelope
  - Configurable request timeout
  - `RailsWebhookOutbox::DeliveryError` for non-2xx responses

### Milestone 3: Async Delivery

- `RailsWebhookOutbox::DeliveryJob` — ActiveJob subclass
  - `queue_as` from configuration
  - `retry_on RailsWebhookOutbox::DeliveryError` with exponential backoff
  - Update delivery record on success (status, response_code, response_body, delivered_at, attempts)
  - Update delivery record on failure (response_code, response_body, attempts, status)
  - Mark as `failed` after max retries exhausted

### Milestone 4: ActiveRecord Integration

- `RailsWebhookOutbox::Dispatchable` concern
  - `dispatches_webhook "event.name", on: :create` — after_create callback
  - `dispatches_webhook "event.name", on: :update` — after_update callback
  - `if:` conditional lambda support
  - `webhook_payload` override method
  - Creates delivery records for all matching active subscriptions
  - Enqueues `DeliveryJob` for each delivery
- `RailsWebhookOutbox.dispatch("event", payload)` — manual dispatch API
  - Finds all active subscriptions for the event
  - Creates delivery records
  - Enqueues delivery jobs

### Milestone 5: Generator and Release Prep

- `rails generate rails_webhook_outbox:install` generator
  - Copies migrations to host app
  - Creates initializer template with documented defaults
- README with usage documentation
- Gemspec metadata finalized (homepage, source_code_uri, changelog_uri)
- 100% RSpec line + branch coverage

---

## 0.2 — Dashboard

- Mountable engine UI (`mount RailsWebhookOutbox::Engine => "/admin/webhooks"`)
- Turbo Streams for live updates
- Dark mode support
- Subscription management CRUD (list, create, edit, enable/disable)
- Delivery log browser with filters (status, event, date range)
- Delivery detail view (request/response, timeline)
- Manual retry button for failed deliveries
- Registered events browser with payload examples

---

## 0.3 — Polish

- Payload versioning
- Rate limiting per subscription
- Stats JSON endpoint (`/admin/webhooks/stats.json`)
- CSV export for deliveries

---