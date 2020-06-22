Rails.application.routes.draw do

  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html
  #
  get  '/activity_logs',                              to: 'activity_logs#index' # only less methods for resource established
  post '/activity_logs',                              to: 'activity_logs#create'# only less methods for resource established
  resources :columns
  resources :conditions
  get  '/db_columns',                                 to: 'db_columns#index'    # only one method for resource established
  get  '/db_schemas',                                 to: 'db_schemas#index'    # only one method for resource established
  get  '/db_schemas/authorizable_schemas',            to: 'db_schemas#authorizable_schemas'
  get  '/db_schemas/validate_user_name',              to: 'db_schemas#validate_user_name'
  get  '/db_tables',                                  to: 'db_tables#index'
#  get  '/db_tables/remaining',                        to: 'db_tables#remaining'
  get  '/db_triggers',                                to: 'db_triggers#index'
  get  '/db_triggers/details',                        to: 'db_triggers#show'
  post '/db_triggers/generate',                       to: 'db_triggers#generate'
  post '/db_triggers/generate_all',                   to: 'db_triggers#generate_all'
  get  '/health_check',                               to: 'health_check#index'  # only one method for resource established
  get  '/health_check/log_file',                      to: 'health_check#log_file'
  get  '/kafka/describe_topic',                       to: 'kafka#describe_topic'
  get  '/kafka/topics',                               to: 'kafka#topics'
  post 'login/do_logon'
  get  'login/check_jwt'
  get  'login/release_info'
  resources :schemas
  resources :schema_rights
  post '/server_control/set_log_level',               to: 'server_control#set_log_level'
  post '/server_control/set_worker_threads_count',    to: 'server_control#set_worker_threads_count'
  post '/server_control/terminate',                   to: 'server_control#terminate'

  resources :tables
  get  '/trigger_dates/:id',                          to: 'tables#trigger_dates'
  resources :users

  root 'login#index'
end
