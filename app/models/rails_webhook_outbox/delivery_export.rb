module RailsWebhookOutbox
  # CSV export of a deliveries scope, produced line by line so a large export is never held
  # in memory. Most recently created deliveries first, in insertion (id) order, which follows
  # created_at except for backfilled rows or clock skew. Capped at ROW_LIMIT so one request
  # can't export an unbounded table. When the cap cuts rows off, a warning row comes first.
  class DeliveryExport
    ROW_LIMIT = 10_000
    BATCH_SIZE = 1000
    HEADERS = [
      "id", "event", "subscription_url", "status", "attempts", "response_code",
      "created_at", "delivered_at", "next_retry_at"
    ].freeze
    # Only what the export writes, plus subscription_id for the URL. Skips the potentially
    # large payload and response_body columns.
    COLUMNS = [
      :id, :event, :subscription_id, :status, :attempts, :response_code,
      :created_at, :delivered_at, :next_retry_at
    ].freeze
    # Spreadsheets treat a cell starting with one of these as a formula (CSV injection).
    FORMULA_PREFIXES = ["=", "+", "-", "@", "\t", "\r"].freeze

    def initialize(scope)
      @scope = scope
    end

    def each_line
      return enum_for(:each_line) unless block_given?

      yield line([truncation_warning]) if truncated?
      yield line(HEADERS)
      @scope.select(*COLUMNS).includes(:subscription).limit(ROW_LIMIT).find_each(batch_size: BATCH_SIZE, order: :desc) do |delivery|
        yield line(row(delivery))
      end
    end

    private

    def row(delivery)
      [
        delivery.id, delivery.event, delivery.subscription.url, delivery.status, delivery.attempts,
        delivery.response_code, iso8601(delivery.created_at), iso8601(delivery.delivered_at),
        iso8601(delivery.next_retry_at)
      ]
    end

    def iso8601(time)
      time.utc.iso8601 if time
    end

    # A cheap probe: is there at least one row beyond the cap?
    def truncated?
      @scope.offset(ROW_LIMIT).exists?
    end

    def truncation_warning
      "# WARNING: limited to the newest #{ROW_LIMIT.to_fs(:delimited)} deliveries; narrow the filters to export the rest"
    end

    def line(cells)
      CSV.generate_line(cells.map { |cell| neutralize(cell) }, row_sep: "\r\n")
    end

    def neutralize(cell)
      cell.is_a?(String) && cell.start_with?(*FORMULA_PREFIXES) ? "'#{cell}" : cell
    end
  end
end
