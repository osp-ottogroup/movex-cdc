Rails.application.routes.draw do
  post 'login/do_logon'

  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html
  #
  get '/db_columns',  to: 'db_columns#index'                                    # only one method for resource established
  get '/db_schemas',  to: 'db_schemas#index'                                    # only one method for resource established
  get '/db_tables',   to: 'db_tables#index'                                     # only one method for resource established
  resources :columns
  resources :schemas
  resources :tables
  resources :users
end
