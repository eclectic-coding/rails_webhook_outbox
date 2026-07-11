RailsWebhookOutbox::Engine.routes.draw do
  root to: "overview#show"

  resources :subscriptions do
    member do
      patch :rotate_secret
    end
  end

  resources :deliveries, only: [:index, :show] do
    member do
      post :retry
    end
  end

  resources :events, only: [:index]
end
