module RailsWebhookOutbox
  class BaseController < ActionController::Base
    protect_from_forgery with: :null_session
    layout "rails_webhook_outbox/application"
    helper RailsWebhookOutbox::ApplicationHelper

    before_action :check_dashboard_enabled

    private

      def check_dashboard_enabled
        head :forbidden unless RailsWebhookOutbox.config.dashboard_enabled
      end
  end
end
