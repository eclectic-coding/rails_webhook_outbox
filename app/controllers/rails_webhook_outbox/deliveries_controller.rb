module RailsWebhookOutbox
  class DeliveriesController < BaseController
    PER_PAGE = 50

    def index
      @status = params[:status] if Delivery.statuses.key?(params[:status])
      @event = params[:event] if RailsWebhookOutbox.config.events.include?(params[:event])
      @from = parse_date(params[:from])
      @to = parse_date(params[:to])
      @page = params[:page].to_i
      @page = 1 if @page < 1

      deliveries = Delivery.order(created_at: :desc)
      deliveries = deliveries.where(status: @status) if @status
      deliveries = deliveries.where(event: @event) if @event
      deliveries = deliveries.where(created_at: @from..) if @from
      deliveries = deliveries.where(created_at: ..@to.end_of_day) if @to

      @total_count = deliveries.count
      @deliveries = deliveries.limit(PER_PAGE).offset((@page - 1) * PER_PAGE)
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

      def parse_date(value)
        Date.parse(value) if value.present?
      rescue ArgumentError
        nil
      end
  end
end
