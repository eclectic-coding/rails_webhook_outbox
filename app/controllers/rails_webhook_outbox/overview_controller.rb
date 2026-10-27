module RailsWebhookOutbox
  class OverviewController < BaseController
    def show
      @overview = Overview.new
    end
  end
end
