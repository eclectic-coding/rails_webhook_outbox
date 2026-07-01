# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_07_01_000002) do
  create_table "orders", force: :cascade do |t|
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.string "status", default: "pending", null: false
    t.string "title", null: false
    t.decimal "total", precision: 10, scale: 2, null: false
    t.datetime "updated_at", null: false
  end

  create_table "webhook_outbox_deliveries", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.string "event", null: false
    t.string "idempotency_key"
    t.datetime "next_retry_at"
    t.json "payload", null: false
    t.text "response_body"
    t.integer "response_code"
    t.integer "status", default: 0, null: false
    t.integer "subscription_id", null: false
    t.datetime "updated_at", null: false
    t.index ["event"], name: "index_webhook_outbox_deliveries_on_event"
    t.index ["idempotency_key"], name: "index_webhook_outbox_deliveries_on_idempotency_key", unique: true
    t.index ["status"], name: "index_webhook_outbox_deliveries_on_status"
    t.index ["subscription_id", "created_at"], name: "idx_on_subscription_id_created_at_000c14e1f7"
    t.index ["subscription_id"], name: "index_webhook_outbox_deliveries_on_subscription_id"
  end

  create_table "webhook_outbox_subscriptions", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "consecutive_failures", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.json "events", default: [], null: false
    t.json "metadata", default: {}
    t.string "previous_secret"
    t.datetime "previous_secret_expires_at"
    t.string "secret", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
  end

  add_foreign_key "webhook_outbox_deliveries", "webhook_outbox_subscriptions", column: "subscription_id"
end
