module RailsWebhookOutbox
  # JSON metrics for monitoring, read from the same Overview the dashboard uses.
  class StatsController < BaseController
    DEFAULT_WINDOW = "24h".freeze
    WINDOW_FORMAT = /\A(\d+)([mhd])\z/
    WINDOW_UNITS = { "m" => 1.minute, "h" => 1.hour, "d" => 1.day }.freeze
    MIN_WINDOW = 1.minute
    MAX_WINDOW = 30.days

    def show
      label = params.fetch(:window, DEFAULT_WINDOW)
      window = parse_window(label)

      if window
        render json: Overview.new(window: window).to_stats(window_label: label)
      else
        render json: { error: "window must look like 15m, 24h, or 7d, between 1m and 30d" }, status: :bad_request
      end
    end

    private

      def parse_window(value)
        match = WINDOW_FORMAT.match(value.to_s)
        return unless match

        window = match[1].to_i * WINDOW_UNITS.fetch(match[2])
        window if window.between?(MIN_WINDOW, MAX_WINDOW)
      end
  end
end
