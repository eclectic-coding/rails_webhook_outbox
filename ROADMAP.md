# Roadmap

> Planned features for **rails_webhook_outbox**.
> Completed items are moved to CHANGELOG.md and removed from this file.
> Shipped sections are removed automatically by `bin/release`.

## 0.1.0 — MVP

### Dummy App

- Add `solid_queue` gem and configure as the development queue adapter
- `RailsWebhookOutbox` initializer with documented defaults
- `Order` model with migration (title, total, status, cancelled_at) as the test host-app model
- `OrdersController` — API-only `create` and `update` actions
- Routes: `resources :orders`
- Seeds: sample subscriptions and orders
- Wire `Order` to `Dispatchable` (`dispatches_webhook` on create/update/cancel)

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