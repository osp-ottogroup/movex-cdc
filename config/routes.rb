Rails.application.routes.draw do

  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html
  #
  get  '/activity_logs',                to: 'activity_logs#index'               # only less methods for resource established
  post '/activity_logs',                to: 'activity_logs#create'              # only less methods for resource established
  resources :columns
  resources :conditions
  get  '/db_columns',                   to: 'db_columns#index'                  # only one method for resource established
  get  '/db_schemas',                   to: 'db_schemas#index'                  # only one method for resource established
  get  '/db_tables',                    to: 'db_tables#index'                   # only one method for resource established
  get  '/db_triggers',                  to: 'db_triggers#index'
  get  '/db_triggers/details',          to: 'db_triggers#show'
  post '/db_triggers/generate',         to: 'db_triggers#generate'
  post '/db_triggers/generate_all',     to: 'db_triggers#generate_all'
  get  '/health_check',                 to: 'health_check#index'                # only one method for resource established
  post '/health_check/set_log_level',   to: 'health_check#set_log_level'
  post 'login/do_logon'
  get  'login/check_jwt'
  resources :schemas
  resources :schema_rights
  resources :tables
  get  '/trigger_dates/:id',            to: 'tables#trigger_dates'
  resources :users

  root 'login#index'
end
