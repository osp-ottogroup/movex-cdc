# Add your own tasks in files placed in lib/tasks ending in .rake,
# for example lib/tasks/capistrano.rake, and they will automatically be available to Rake.

# Ensure models and helpers are available at origin without require_relative
model_path = "#{Dir.pwd}/app/models"
$LOAD_PATH.unshift(model_path) unless $LOAD_PATH.include?(model_path)
helper_path = "#{Dir.pwd}/app/helpers"
$LOAD_PATH.unshift(helper_path) unless $LOAD_PATH.include?(helper_path)

require_relative 'config/application'

Rails.application.load_tasks
