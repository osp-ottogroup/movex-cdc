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

require 'yaml'

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

    def self.log_attribute(key, value)
      puts "#{key.ljust(35, ' ')} #{value}"
    end

    def self.set_attrib_from_env(key, default=nil)
      up_key = key.to_s.upcase
      value = default
      value = Trixx::Application.config.send(key) if Trixx::Application.config.respond_to?(key)
      value = ENV[up_key] if ENV[up_key]
      Trixx::Application.config.send("#{key}=", value)                          # ensure all config methods are defined whether with values or without
    end

    def self.set_and_log_attrib_from_env(key, default=nil)
      Trixx::Application.set_attrib_from_env(key, default)
      Trixx::Application.log_attribute(key.to_s.upcase, Trixx::Application.config.send(key))
    end


    puts "\nStarting TriXX application at #{Time.now}:"
    Trixx::Application.log_attribute('RAILS_ENV', Rails.env)

    # Load configuration file, should always exist, at leastwith default values
    config.trixx_run_config = ENV['TRIXX_RUN_CONFIG'] || "#{Rails.root}/config/trixx_run.yml"
    Trixx::Application.log_attribute('TRIXX_RUN_CONFIG', config.trixx_run_config)
    run_config = YAML.load_file(config.trixx_run_config)
    run_config.each do |key, value|
      config.send "#{key.downcase}=", value                                           # copy file content to config
    end
    config.log_level = config.log_level.to_sym if config.log_level.class == String
    Trixx::Application.log_attribute('LOG_LEVEL', config.log_level)

    config.trixx_db_type = ENV['TRIXX_DB_TYPE'] || config.trixx_db_type
    Trixx::Application.log_attribute('TRIXX_DB_TYPE', config.trixx_db_type)

    supported_db_types = ['ORACLE', 'SQLITE']
    raise "Unsupported value '#{config.trixx_db_type}' for configuration attribute 'TRIXX_DB_TYPE'! Supported values are #{supported_db_types}" unless supported_db_types.include?(config.trixx_db_type)

    if Rails.env.test?
      Trixx::Application.set_attrib_from_env(:trixx_db_password, 'trixx')
      Trixx::Application.set_attrib_from_env(:trixx_db_victim_password, 'trixx_victim')
    end

    case config.trixx_db_type
    when 'ORACLE' then
      if Rails.env.test?                                                        # prevent test-user from overwriting development or production structures in DB
        config.trixx_db_user            = "test_#{config.respond_to?(:trixx_db_user) ? config.trixx_db_user : 'trixx'}"
        Trixx::Application.set_and_log_attrib_from_env(:trixx_db_victim_user, 'trixx_victim') if Rails.env.test? # Schema for tables observed by trixx
        Trixx::Application.set_attrib_from_env(:trixx_db_system_password, 'oracle')
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

    Trixx::Application.set_and_log_attrib_from_env(:trixx_db_user)
    Trixx::Application.set_attrib_from_env(:trixx_db_password)
    Trixx::Application.set_and_log_attrib_from_env(:trixx_db_url)
    Trixx::Application.set_and_log_attrib_from_env(:trixx_kafka_seed_broker, '/dev/null')
    Trixx::Application.set_and_log_attrib_from_env(:trixx_initial_worker_threads)

    # Verify mandatory settings
    raise "Missing configuration value for 'TRIXX_DB_USER'! Aborting..."            unless config.trixx_db_user
    raise "Missing configuration value for 'TRIXX_DB_PASSWORD'! Aborting..."        unless config.trixx_db_password
    raise "Missing configuration value for 'TRIXX_KAFKA_SEED_BROKER'! Aborting..."  unless config.trixx_kafka_seed_broker

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
