# Upgrading

Notes for upgrades that need action from you, newest version first. For everything that changed in a
release, see the [CHANGELOG](CHANGELOG.md).

## Upgrading to 0.5.0

**Not breaking.** This release adds a column and two indexes on the deliveries table. Run the
migrations: until the column exists, creating a delivery fails, and without the indexes the
dashboard and the stats endpoint stay slow on a large table.

### What changed

A new migration adds a nullable `payload_version` column to `webhook_outbox_deliveries`. Every
webhook now carries a `version` key in its JSON body and an `X-Webhook-Version` header (`1` unless
you configure `config.payload_versions`). Subscribers that ignore unknown keys and headers are
unaffected. Deliveries created before the migration have no stored version and are sent as the
default.

Two more migrations add indexes on `webhook_outbox_deliveries`:

- `delivered_at`: the latency figures on the dashboard overview filter and sort by it.
- `created_at`: the deliveries list sorts by it, and the stats endpoint's success rate filters on
  it. Without it, each of those scans and sorts the whole table.

Both keep these queries a bounded index scan however many deliveries you have.

### Steps

1. Update the gem:

   ```bash
   bundle update rails_webhook_outbox
   ```

2. Run the migration (the engine adds its migrations to your app, so there is nothing to copy):

   ```bash
   bin/rails db:migrate
   ```

On a very large deliveries table, building an index can take a while and, depending on your
database, lock writes to the table. If that matters, run the migrations in a quiet period, or create
the indexes yourself with your database's online option (for example `CREATE INDEX CONCURRENTLY` on
PostgreSQL) before migrating. The migrations skip an index that already exists.

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

### If you ran the install generator on an earlier version

Before 0.4.0, `rails generate rails_webhook_outbox:install` also copied the engine's table migrations
into your app's `db/migrate`. The engine adds those same migrations to your app on its own, so with
the copies present `db:migrate` fails:

```
ActiveRecord::DuplicateMigrationNameError: Multiple migrations have the name CreateWebhookOutboxSubscriptions.
```

To fix it, delete the copies and migrate. The engine's migrations now skip tables, columns, and
indexes that already exist, so they are safe to run against a database the copies already built:

```bash
rm db/migrate/*_create_webhook_outbox_subscriptions.rb \
   db/migrate/*_create_webhook_outbox_deliveries.rb
bin/rails db:migrate
```

Commit the deletions. `db:migrate:status` will keep listing the old copied versions as `NO FILE`;
that is harmless. The run also adds anything the copies lacked, such as the unique index on
`idempotency_key`, and creates the new `webhook_outbox_delivery_attempts` table.

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
