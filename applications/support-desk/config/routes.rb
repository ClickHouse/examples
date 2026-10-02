Rails.application.routes.draw do
  root "tickets#index"
  resource :session, only: [:new, :create, :destroy]
  resources :tickets, only: [:index, :new, :create, :show] do
    post :claim, on: :member
    post :close, on: :member
    post :reopen, on: :member
    resources :replies, only: [:create]
  end
end
