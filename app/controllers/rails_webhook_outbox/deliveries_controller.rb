module RailsWebhookOutbox
  class DeliveriesController < BaseController
    PER_PAGE = 50

    def index
      deliveries = filtered_deliveries

      respond_to do |format|
        format.html do
          @page = params[:page].to_i
          @page = 1 if @page < 1

          @total_count = deliveries.count
          @deliveries = deliveries.order(created_at: :desc).limit(PER_PAGE).offset((@page - 1) * PER_PAGE)
        end
        format.csv { stream_csv(deliveries) }
      end
    end

    def show
      @delivery = Delivery.find(params[:id])
    end

    def retry
      @delivery = Delivery.find(params[:id])
      @delivery.update!(status: :pending, next_retry_at: nil)
      DeliveryJob.perform_later(@delivery)

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to delivery_path(@delivery) }
      end
    end

    private

      # Shared by the HTML list and the CSV export so they always agree on what a filter means.
      def filtered_deliveries
        @status = params[:status] if Delivery.statuses.key?(params[:status])
        @event = params[:event] if RailsWebhookOutbox.config.events.include?(params[:event])
        @from = parse_date(params[:from])
        @to = parse_date(params[:to])

        deliveries = Delivery.all
        deliveries = deliveries.where(status: @status) if @status
        deliveries = deliveries.where(event: @event) if @event
        deliveries = deliveries.where(created_at: @from..) if @from
        deliveries = deliveries.where(created_at: ..@to.end_of_day) if @to
        deliveries
      end

      def stream_csv(deliveries)
        headers["Content-Disposition"] = %(attachment; filename="webhook-deliveries-#{Time.current.utc.strftime("%Y%m%d-%H%M%S")}.csv")
        # no-cache stops Rack::ETag from buffering the whole body; X-Accel-Buffering does the same for nginx.
        headers["Cache-Control"] = "no-cache"
        headers["X-Accel-Buffering"] = "no"
        self.response_body = DeliveryExport.new(deliveries).each_line
      end

      def parse_date(value)
        Date.parse(value) if value.present?
      rescue ArgumentError
        nil
      end
  end
end
