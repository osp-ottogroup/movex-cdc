# This file is used by Rack-based servers to start the application.

require_relative 'config/environment'

# Doing initialization after startup
InitializationJob.set(wait: 1.seconds).perform_later unless Rails.env.test?    # don't run jobs in test

run Rails.application
