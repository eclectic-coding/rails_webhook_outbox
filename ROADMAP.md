# Roadmap

> Planned features for **rails_webhook_outbox**.
> Completed items are moved to CHANGELOG.md and removed from this file.
> Shipped sections are removed automatically by `bin/release`.


## 0.4.0 — Dashboard

Tracked in [#12](https://github.com/eclectic-coding/rails_webhook_outbox/issues/12); one PR per item.

- Delivery detail timeline — chronological attempt history (needs per-attempt data; `Delivery` only stores the latest attempt today)
- Live overview — Turbo Stream updates for the overview counts and recent failures

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
