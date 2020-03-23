require_relative 'boot'

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "sprockets/railtie"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Trixx
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 6.0

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    config.middleware.insert_before 0, Rack::Cors do
      allow do
        origins '*'
        resource(
            '*',
            headers: :any,
            methods: [:get, :patch, :put, :delete, :post, :options]
        )
      end
    end

    config.trixx_db_type = ENV['TRIXX_DB_TYPE'] || 'SQLITE'

    supported_db_types = ['ORACLE', 'SQLITE']
    raise "Unsupported value '#{config.trixx_db_type}' for configuration attribute 'TRIXX_DB_TYPE'! Supported values are #{supported_db_types}" unless supported_db_types.include?(config.trixx_db_type)

    config.trixx_db_user                = ENV['TRIXX_DB_USER']
    config.trixx_db_password            = ENV['TRIXX_DB_PASSWORD']
    config.trixx_db_url                 = ENV['TRIXX_DB_URL']
    config.trixx_kafka_seed_broker      = ENV['TRIXX_KAFKA_SEED_BROKER'] || '/dev/null'
    config.trixx_initial_worker_threads = (ENV['TRIXX_INITIAL_WORKER_THREADS'] || '3').to_i

    # Verify mandatory settings
    if Rails.env.test?
      config.trixx_db_password        = config.trixx_db_password        || 'trixx'
      config.trixx_db_victim_password = ENV['TRIXX_DB_VICTIM_PASSWORD'] || 'trixx_victim'
    end
    case config.trixx_db_type
    when 'ORACLE' then
      if Rails.env.test?                                                        # prevent test-user from overwriting development or production structures in DB
        config.trixx_db_user            = "test_#{config.trixx_db_user || 'trixx'}"
        config.trixx_db_victim_user     = ENV['TRIXX_DB_VICTIM_USER']     || 'trixx_victim'   # Schema for tables observed by trixx
        config.trixx_db_system_password = ENV['TRIXX_DB_SYSTEM_PASSWORD'] || 'oracle'
      end
      raise "Missing configuration value for 'TRIXX_DB_URL'! Aborting..."       unless config.trixx_db_url
    when 'SQLITE' then
      config.trixx_db_user              = 'main'
      if Rails.env.test?
        config.trixx_db_victim_user     = 'main'  if Rails.env.test?
      end
    else
      raise "unsupported DB type '#{config.trixx_db_type}'"
    end
    raise "Missing configuration value for 'TRIXX_DB_USER'! Aborting..."            unless config.trixx_db_user
    raise "Missing configuration value for 'TRIXX_DB_PASSWORD'! Aborting..."        unless config.trixx_db_password
    raise "Missing configuration value for 'TRIXX_KAFKA_SEED_BROKER'! Aborting..."  unless config.trixx_kafka_seed_broker

    msg = "\nStarting TriXX application at #{Time.now}:
RAILS_ENV                     = #{Rails.env}
TRIXX_DB_TYPE                 = #{config.trixx_db_type}
TRIXX_DB_URL                  = #{config.trixx_db_url}
TRIXX_DB_USER                 = #{config.trixx_db_user}
TRIXX_KAFKA_SEED_BROKER       = #{config.trixx_kafka_seed_broker}
TRIXX_INITIAL_WORKER_THREADS  = #{config.trixx_initial_worker_threads}
"

    msg << "TRIXX_DB_VICTIM_USER          = #{config.trixx_db_victim_user}" if Rails.env.test?

    puts msg

    # check if database supports partitioning (possible and licensed)
    def partitioning
      if !defined? @trixx_db_partitioning
        @trixx_db_partitioning = case config.trixx_db_type
                                 when 'ORACLE' then
                                   TableLess.select_one("SELECT Value FROM v$Option WHERE Parameter='Partitioning'") == 'TRUE'
                                 else
                                   false
                                 end
        Rails.logger.info "Partitioning = #{@trixx_db_partitioning} for this #{config.trixx_db_type} database"
      end
      @trixx_db_partitioning
    end

  end
end
