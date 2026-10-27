require "rails_helper"

RSpec.describe "Database migrations" do
  describe "webhook_outbox_subscriptions" do
    it "has the expected columns" do
      columns = ActiveRecord::Base.connection.columns(:webhook_outbox_subscriptions)
      column_names = columns.map(&:name)

      expect(column_names).to include("url", "secret", "events", "active", "description", "metadata", "created_at", "updated_at")
    end

    it "enforces not-null constraints" do
      columns = ActiveRecord::Base.connection.columns(:webhook_outbox_subscriptions)
      not_null_columns = columns.select { |c| !c.null }.map(&:name)

      expect(not_null_columns).to include("url", "secret", "events", "active")
    end
  end

  describe "webhook_outbox_deliveries" do
    it "has the expected columns" do
      columns = ActiveRecord::Base.connection.columns(:webhook_outbox_deliveries)
      column_names = columns.map(&:name)

      expect(column_names).to include(
        "subscription_id", "event", "payload", "status",
        "response_code", "response_body", "attempts",
        "delivered_at", "next_retry_at", "created_at", "updated_at"
      )
    end

    it "enforces not-null constraints" do
      columns = ActiveRecord::Base.connection.columns(:webhook_outbox_deliveries)
      not_null_columns = columns.select { |c| !c.null }.map(&:name)

      expect(not_null_columns).to include("subscription_id", "event", "payload", "status", "attempts")
    end

    it "has indexes on status, event, and subscription+created_at" do
      indexes = ActiveRecord::Base.connection.indexes(:webhook_outbox_deliveries)
      index_columns = indexes.map(&:columns)

      expect(index_columns).to include(["status"])
      expect(index_columns).to include(["event"])
      expect(index_columns).to include(["subscription_id", "created_at"])
    end
  end

  describe "webhook_outbox_delivery_attempts" do
    it "has the expected columns" do
      column_names = ActiveRecord::Base.connection.columns(:webhook_outbox_delivery_attempts).map(&:name)

      expect(column_names).to include(
        "delivery_id", "attempt_number", "outcome",
        "response_code", "response_body", "duration_ms", "created_at"
      )
    end

    it "enforces not-null constraints" do
      columns = ActiveRecord::Base.connection.columns(:webhook_outbox_delivery_attempts)
      not_null_columns = columns.select { |c| !c.null }.map(&:name)

      expect(not_null_columns).to include("delivery_id", "attempt_number", "outcome", "created_at")
    end

    it "has an index on delivery and attempt number" do
      indexes = ActiveRecord::Base.connection.indexes(:webhook_outbox_delivery_attempts)

      expect(indexes.map(&:columns)).to include(["delivery_id", "attempt_number"])
    end

    it "cascades deletes from deliveries" do
      foreign_key = ActiveRecord::Base.connection.foreign_keys(:webhook_outbox_delivery_attempts).sole

      expect(foreign_key.to_table).to eq("webhook_outbox_deliveries")
      expect(foreign_key.on_delete).to eq(:cascade)
    end
  end
end