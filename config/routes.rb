RailsWebhookOutbox::Engine.routes.draw do
  root to: "overview#show"

  # Explicit :only keeps new/edit routes on Rails 7.2 in api_only host apps,
  # where resources would otherwise omit them.
  resources :subscriptions, only: [:index, :show, :new, :create, :edit, :update, :destroy] do
    member do
      patch :rotate_secret
      patch :toggle
    end
  end

  resources :deliveries, only: [:index, :show] do
    member do
      post :retry
    end
  end

  resources :events, only: [:index]

  # JSON only: /stats and /stats.json; any other format has no route.
  resource :stats, only: [:show], defaults: { format: "json" }, constraints: { format: "json" }
end
