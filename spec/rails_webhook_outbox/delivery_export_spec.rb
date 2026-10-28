require "rails_helper"

RSpec.describe RailsWebhookOutbox::DeliveryExport do
  let(:subscription) do
    RailsWebhookOutbox::Subscription.create!(url: "https://example.com/webhooks", events: ["order.created"])
  end

  def create_delivery(event: "order.created", **attrs)
    RailsWebhookOutbox::Delivery.create!(subscription: subscription, event: event, payload: { id: 1 }, **attrs)
  end

  def lines(scope = RailsWebhookOutbox::Delivery.all)
    described_class.new(scope).each_line.to_a
  end

  # Parsed rows, header included.
  def rows(scope = RailsWebhookOutbox::Delivery.all)
    CSV.parse(lines(scope).join)
  end

  it "starts with the header row" do
    expect(rows.first).to eq(%w[id event subscription_url status attempts response_code created_at delivered_at next_retry_at])
  end

  it "ends every line with CRLF" do
    create_delivery

    expect(lines).to all(end_with("\r\n"))
  end

  it "returns only the header for an empty scope" do
    expect(rows.size).to eq(1)
  end

  it "writes one row per delivery with the documented columns" do
    delivery = create_delivery(status: :delivered, attempts: 2, response_code: 200, delivered_at: Time.utc(2026, 10, 28, 12, 0, 5))
    delivery.update_column(:created_at, Time.utc(2026, 10, 28, 12, 0, 0))

    expect(rows.last).to eq([
      delivery.id.to_s, "order.created", "https://example.com/webhooks", "delivered", "2", "200",
      "2026-10-28T12:00:00Z", "2026-10-28T12:00:05Z", nil
    ])
  end

  it "leaves empty cells for missing values" do
    create_delivery

    expect(rows.last.values_at(5, 7, 8)).to eq([nil, nil, nil])
  end

  it "round-trips fields containing commas, quotes, and newlines" do
    create_delivery(event: %(odd,"event"\nname))

    expect(rows.last[1]).to eq(%(odd,"event"\nname))
  end

  describe "CSV formula injection" do
    ["=SUM(A1)", "+1", "-1", "@cmd", "\tcmd", "\rcmd"].each do |event|
      it "neutralises a cell starting with #{event.inspect}" do
        create_delivery(event: event)

        expect(rows.last[1]).to eq("'#{event}")
      end
    end

    it "leaves ordinary text and numbers untouched" do
      create_delivery(event: "order.created", attempts: 3)

      expect(rows.last.values_at(1, 4)).to eq(["order.created", "3"])
    end
  end

  describe "row cap" do
    before { stub_const("#{described_class}::ROW_LIMIT", 2) }

    it "exports the newest deliveries first and stops at ROW_LIMIT" do
      create_delivery(event: "oldest")
      create_delivery(event: "middle")
      create_delivery(event: "newest")

      events = rows.drop(2).map { |row| row[1] }

      expect(events).to eq(%w[newest middle])
    end

    it "puts a warning row before the header when rows were cut off" do
      3.times { create_delivery }

      expect(rows.first).to eq(["# WARNING: limited to the newest 2 deliveries; narrow the filters to export the rest"])
      expect(rows.second.first).to eq("id")
      expect(rows.size).to eq(4)
    end

    it "formats the limit with delimiters in the warning" do
      stub_const("#{described_class}::ROW_LIMIT", 10_000)
      allow_any_instance_of(described_class).to receive(:truncated?).and_return(true)

      expect(rows.first.first).to include("newest 10,000 deliveries")
    end

    it "does not warn when exactly ROW_LIMIT deliveries match" do
      2.times { create_delivery }

      expect(rows.first.first).to eq("id")
      expect(rows.size).to eq(3)
    end
  end

  it "does not load the payload or response_body columns" do
    create_delivery(response_body: "x" * 100)
    queries = []
    # The batch reads only; the truncation probe is `SELECT 1 AS one`.
    collector = lambda do |*, payload|
      sql = payload[:sql]
      queries << sql if sql.match?(/\ASELECT .* FROM "webhook_outbox_deliveries"/) && !sql.include?("AS one")
    end

    ActiveSupport::Notifications.subscribed(collector, "sql.active_record") { lines }

    expect(queries).not_to be_empty
    # A bare `table.*` select would load every column without naming payload.
    expect(queries).to all(satisfy { |sql| sql.include?('"event"') && !sql.include?(".*") })
    expect(queries).to all(satisfy { |sql| !sql.include?("payload") && !sql.include?("response_body") })
  end

  it "orders by insertion (id), newest first, even when created_at disagrees" do
    first = create_delivery(event: "inserted.first")
    first.update_column(:created_at, 1.hour.from_now)
    create_delivery(event: "inserted.second")

    expect(rows.drop(1).map { |row| row[1] }).to eq(%w[inserted.second inserted.first])
  end

  it "reads across several batches" do
    stub_const("#{described_class}::BATCH_SIZE", 2)
    5.times { |i| create_delivery(event: "event.#{i}") }

    expect(rows.size).to eq(6)
  end

  it "returns an enumerator when called without a block, so it can be streamed" do
    expect(described_class.new(RailsWebhookOutbox::Delivery.all).each_line).to be_a(Enumerator)
  end
end
