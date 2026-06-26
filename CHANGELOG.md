# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `RailsWebhookOutbox::Delivery` model — status enum (pending/delivered/failed), belongs-to subscription, event and payload validations, `retryable` / `delivered` / `failed` scopes
- `RailsWebhookOutbox::Subscription` model — URL/format and events presence validations, auto-generated HMAC secret on create, `active` scope, and `subscribes_to?(event)` query method
- `RailsWebhookOutbox::Configuration` — configuration DSL with defaults for events, signing algorithm, signing header, max retries, retry backoff, request timeout, and delivery job queue
- `RailsWebhookOutbox.configure` block API, `.config` / `.configuration` accessors, and `.reset_configuration!`
- Validation for `signing_algorithm` (sha256, sha384, sha512) and `retry_backoff` (exponential, linear)
- Database migrations for `webhook_outbox_subscriptions` and `webhook_outbox_deliveries` tables with indexes on status, event, and subscription+created_at

### Fixed
- `spec/rails_helper.rb` — removed broken `require_relative '../config/environment'`; engine migration path now auto-appended and test DB auto-migrated

[Unreleased]: https://github.com/eclectic-coding/rails_webhook_outbox/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/eclectic-coding/rails_webhook_outbox/releases/tag/v0.1.0
