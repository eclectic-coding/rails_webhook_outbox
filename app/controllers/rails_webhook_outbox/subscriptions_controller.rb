module RailsWebhookOutbox
  class SubscriptionsController < BaseController
    def index
      @subscriptions = Subscription.order(created_at: :desc)
    end

    def show
      @subscription = Subscription.find(params[:id])
    end

    def new
      @subscription = Subscription.new
    end

    def create
      @subscription = Subscription.new(subscription_params)

      if @subscription.save
        redirect_to subscription_path(@subscription)
      else
        render :new, status: 422
      end
    end

    def edit
      @subscription = Subscription.find(params[:id])
    end

    def update
      @subscription = Subscription.find(params[:id])

      if @subscription.update(subscription_params)
        redirect_to subscription_path(@subscription)
      else
        render :edit, status: 422
      end
    end

    # Enable/disable from the index. The button sends the state it wants, not "flip", so a
    # stale page (or a second tab) can't invert someone else's change.
    def toggle
      @subscription = Subscription.find(params[:id])
      @subscription.update!(active: ActiveModel::Type::Boolean.new.cast(params.require(:active)))

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to subscriptions_path }
      end
    end

    def rotate_secret
      @subscription = Subscription.find(params[:id])
      @subscription.rotate_secret!
      redirect_to subscription_path(@subscription)
    rescue RailsWebhookOutbox::SecretRotationError
      redirect_to subscription_path(@subscription, rotation_error: true)
    end

    private

      def subscription_params
        permitted = params.require(:subscription).permit(:url, :description, :active, :rate_limit_per_minute, events: [])
        raw_events = params[:subscription][:events]

        if raw_events.is_a?(String)
          permitted[:events] = raw_events.split(",").map(&:strip).reject(&:empty?)
        elsif permitted.key?(:events)
          permitted[:events] = Array(permitted[:events]).map(&:to_s).map(&:strip).reject(&:empty?)
        end

        permitted
      end
  end
end
