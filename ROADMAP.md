# Roadmap

> Planned features for **rails_webhook_outbox**.
> Completed items are moved to CHANGELOG.md and removed from this file.
> Shipped sections are removed automatically by `bin/release`.

## 0.1.0 — MVP

### Foundation

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

### Signing and HTTP Delivery

- `RailsWebhookOutbox::Signature` module
  - `.sign(payload, secret, algorithm)` — HMAC hex digest
  - `.header_value(payload, secret)` — formatted `"sha256=abcdef..."` string
- `RailsWebhookOutbox::Sender` service
  - HTTP POST with `Net::HTTP`
  - Request headers: Content-Type, X-Webhook-Signature, X-Webhook-Event, X-Webhook-Delivery, X-Webhook-Timestamp
  - JSON body with `event`, `delivered_at`, and `data` envelope
  - Configurable request timeout
  - `RailsWebhookOutbox::DeliveryError` for non-2xx responses

### Async Delivery

- `RailsWebhookOutbox::DeliveryJob` — ActiveJob subclass
  - `queue_as` from configuration
  - `retry_on RailsWebhookOutbox::DeliveryError` with exponential backoff
  - Update delivery record on success (status, response_code, response_body, delivered_at, attempts)
  - Update delivery record on failure (response_code, response_body, attempts, status)
  - Mark as `failed` after max retries exhausted

### ActiveRecord Integration

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

### Generator and Release Prep

- `rails generate rails_webhook_outbox:install` generator
  - Copies migrations to host app
  - Creates initializer template with documented defaults
- README with usage documentation
- 100% RSpec line + branch coverage

---

## 0.2.0 — Hardening

- Event validation — raise on unregistered event names
- Idempotency key (UUID) stored on Delivery record for subscriber deduplication
- Configurable payload size limit
- Populate `next_retry_at` on retryable failures
- Test mode (`RailsWebhookOutbox.config.test_mode = true`) to suppress HTTP calls
- In-memory delivery capture for assertions
- RSpec matchers — `expect { ... }.to dispatch_webhook("order.created")`

---

## 0.3.0 — Observability & Ops

- `ActiveSupport::Notifications` instrumentation (`webhook.delivered`, `webhook.failed`)
- Structured logging in Sender and DeliveryJob
- Secret rotation with dual-secret grace period
- Circuit breaker — auto-disable subscriptions after N consecutive failures
- Rake tasks (`webhook_outbox:retry_failed`, `webhook_outbox:list_subscriptions`, `webhook_outbox:cleanup[days]`)

---

## 0.4.0 — Dashboard

- Mountable engine UI (`mount RailsWebhookOutbox::Engine => "/admin/webhooks"`)
- Turbo Streams for live updates
- Dark mode support
- Subscription management CRUD (list, create, edit, enable/disable)
- Delivery log browser with filters (status, event, date range)
- Delivery detail view (request/response, timeline)
- Manual retry button for failed deliveries
- Registered events browser with payload examples

---

## 0.5.0 — Polish

- Payload versioning
- Rate limiting per subscription
- Stats JSON endpoint (`/admin/webhooks/stats.json`)
- CSV export for deliveries
- Old delivery cleanup — configurable retention period and pruning
- Dead letter hook — callback/notification when delivery exhausts all retries
- Delivery latency tracking (`delivered_at - created_at`)

---

## 0.6.0 — Stable API

- `RailsWebhookOutbox.deprecator` — memoized `ActiveSupport::Deprecation` instance for future breaking-change warnings
- YARD documentation on all public classes and methods
- Compatibility matrix in README (Rails × Ruby versions)
- `CONTRIBUTING.md` — setup, workflow, test commands, release process
- Audit and remove unused engine boilerplate
- API surface review — remove or deprecate any internal classes exposed publicly
- Freeze public API contract: `Configuration`, `Subscription`, `Delivery`, `Dispatchable`, `Sender`, `Signature`, `DeliveryJob`

---