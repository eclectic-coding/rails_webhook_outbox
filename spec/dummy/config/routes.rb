Rails.application.routes.draw do
  mount RailsWebhookOutbox::Engine => "/rails_webhook_outbox"
  resources :orders, only: [:create, :update]
end
