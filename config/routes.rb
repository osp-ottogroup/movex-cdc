Rails.application.routes.draw do
  post 'login/do_logon'

  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html
  #
  get  '/db_columns',               to: 'db_columns#index'                      # only one method for resource established
  get  '/db_schemas',               to: 'db_schemas#index'                      # only one method for resource established
  get  '/db_tables',                to: 'db_tables#index'                       # only one method for resource established
  get  '/db_triggers',              to: 'db_triggers#index'
  get  '/db_triggers/details',      to: 'db_triggers#show'
  post '/db_triggers/generate',     to: 'db_triggers#generate'
  post '/db_triggers/generate_all', to: 'db_triggers#generate_all'
  resources :columns
  resources :conditions
  resources :schemas
  resources :tables
  resources :users
end
