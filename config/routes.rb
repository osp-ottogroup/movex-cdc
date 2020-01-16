Rails.application.routes.draw do
  post 'login/do_logon'

  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html
  #
  get '/db_tables', to: 'db_tables#index'
  resources :db_columns
  resources :db_schemas
  # resources :db_tables
  resources :columns
  resources :schemas
  resources :tables
  resources :users
end
