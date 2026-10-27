# Upgrading

Notes for upgrades that need action from you, newest version first. For everything that changed in a
release, see the [CHANGELOG](CHANGELOG.md).

## Upgrading to 0.4.0

**This release has a breaking change: it requires a new database table.** Run the migration _before_
the 0.4.0 code starts processing deliveries.

### What changed

`DeliveryJob` now records every HTTP attempt as a `RailsWebhookOutbox::DeliveryAttempt` in the new
`webhook_outbox_delivery_attempts` table. This is the data behind the delivery timeline in the
dashboard. Previously only the latest response was kept on the delivery itself.

### Steps

1. Update the gem:

   ```bash
   bundle update rails_webhook_outbox
   ```

2. Run the migration. The engine adds its migrations to your app's migration paths, so there is
   nothing to copy:

   ```bash
   bin/rails db:migrate
   ```

3. Confirm it ran:

   ```bash
   bin/rails db:migrate:status | grep delivery_attempts
   # up     20261027000001  Create webhook outbox delivery attempts
   ```

In a deploy pipeline, run `db:migrate` before the new code starts serving requests or running jobs
(the usual release-phase step on most hosts).

### If you deploy the code without migrating

`DeliveryJob` sends the HTTP request first and records the attempt afterwards. Without the table,
recording the attempt raises `ActiveRecord::StatementInvalid`, so:

- the webhook **is still sent** to the subscriber, but the delivery is left `pending` with
  `attempts: 0`, and the engine's `DeliveryError` retry does not apply to this error;
- every job fails the same way until the migration is run.

Run `db:migrate`, then re-enqueue the stuck deliveries:

```ruby
RailsWebhookOutbox::Delivery.pending.find_each { |d| RailsWebhookOutbox::DeliveryJob.perform_later(d) }
```

The subscriber will receive those webhooks a second time. It can deduplicate them with the
`X-Webhook-Delivery` header, which is stable across attempts. (`webhook_outbox:retry_failed` does not
help here: it only re-enqueues `failed` deliveries.)

### Existing data

Deliveries created before the upgrade have no attempt history; it starts with the first attempt made
after the migration. Nothing is backfilled.

### Downgrading

Downgrading the gem back to 0.3.0 is safe without rolling the migration back: 0.3.0 never reads the
table, and the foreign key cascades on delete, so `webhook_outbox:cleanup` keeps working.
