Rails.application.routes.draw do
  get 'table/tables'
  get 'user/users'

  devise_for :users
  get 'home/index'

  resources :users, only: [:show, :edit]

  root 'home#index'
end
