Rails.application.routes.draw do
  mount RailsWebhookOutbox::Engine => "/rails_webhook_outbox"
end
