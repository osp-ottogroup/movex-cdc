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
require 'java'


# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Trixx
  class Application < Rails::Application
    # Will be calling Java classes from this JRuby script
    include Java

    # Need to import System to avoid "uninitialized constant System (NameError)"
    import java.lang.System


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

    def self.maximum_initial_worker_threads
      retval = nil                                                              # No limit as default
      retval = 1 if config.trixx_db_type == 'SQLITE'
      retval
    end

    def self.log_attribute(key, value)
      if value.nil? || value == ''
        outval = '< not set >'
      else
        if key['PASSWORD']
          outval = '*****'
        else
          outval = value
        end
      end
      puts "#{key.ljust(40, ' ')} #{outval}"
    end

    # Return print value to log
    def self.set_attrib_from_env(key, options={})
      up_key = key.to_s.upcase
      value = options[:default]
      value = Trixx::Application.config.send(key) if Trixx::Application.config.respond_to?(key)
      value = ENV[up_key] if ENV[up_key]                                        # Environment over previous config value
      value = value.to_s.upcase   if options[:upcase]
      value = value.to_s.downcase if options[:downcase]
      value = value.to_i          if options[:integer]
      log_value = value
      if !value.nil?
        if !options[:maximum].nil? && value > options[:maximum]
          log_value = "#{options[:maximum]}, configured value #{value} reduced to allowed maximum"
          value = options[:maximum]
        end

        if !options[:minimum].nil? && value < options[:minimum]
          raise "Configuration attribute #{up_key} (#{log_value}) should be at least #{options[:minimum]}"
        end
      end
      Trixx::Application.config.send("#{key}=", value)                          # ensure all config methods are defined whether with values or without

      raise "Missing configuration value for '#{up_key}'! Aborting..." if !options[:accept_empty] && Trixx::Application.config.send(key).nil?
      log_value
    end

    def self.set_and_log_attrib_from_env(key, options={})
      Trixx::Application.log_attribute(key.to_s.upcase, set_attrib_from_env(key, options))
    end


    puts "\nStarting TriXX application at #{Time.now}:"
    Trixx::Application.log_attribute('RAILS_ENV', Rails.env)
    Trixx::Application.log_attribute('RAILS_MAX_THREADS', ENV['RAILS_MAX_THREADS'])

    # Load configuration file, should always exist, at leastwith default values
    config.trixx_run_config = ENV['TRIXX_RUN_CONFIG'] || "#{Rails.root}/config/trixx_run.yml"
    Trixx::Application.log_attribute('TRIXX_RUN_CONFIG', config.trixx_run_config)
    run_config = YAML.load_file(config.trixx_run_config)
    run_config.each do |key, value|
      config.send "#{key.downcase}=", value                                     # copy file content to config
    end
    Trixx::Application.set_and_log_attrib_from_env(:log_level, downcase: true)
    config.log_level = config.log_level.to_sym if config.log_level && config.log_level.class == String
    config.log_level = (Rails.env.production? ? :info : :debug) unless config.log_level                  # Default log level is already set to :debug at this point

    Trixx::Application.set_and_log_attrib_from_env(:trixx_db_type, upcase: true)

    supported_db_types = ['ORACLE', 'SQLITE']
    raise "Unsupported value '#{config.trixx_db_type}' for configuration attribute 'TRIXX_DB_TYPE'! Supported values are #{supported_db_types}" unless supported_db_types.include?(config.trixx_db_type)

    if Rails.env.test?
      Trixx::Application.set_attrib_from_env(:trixx_db_password, default: 'trixx')
      Trixx::Application.set_attrib_from_env(:trixx_db_victim_password, default: 'trixx_victim')
    end

    case config.trixx_db_type
    when 'ORACLE' then
      Trixx::Application.set_and_log_attrib_from_env(:trixx_db_sys_password, default: 'oracle', accept_empty: !Rails.env.test?) if Trixx::Application.config.respond_to?(:trixx_db_sys_password) || ENV['TRIXX_DB_SYS_PASSWORD']
      if Rails.env.test?                                                        # prevent test-user from overwriting development or production structures in DB
        config.trixx_db_user            = "test_#{config.respond_to?(:trixx_db_user) ? config.trixx_db_user : 'trixx'}"
        Trixx::Application.set_attrib_from_env(:trixx_db_victim_user, default: 'trixx_victim')
        config.trixx_db_victim_user = config.trixx_db_victim_user.upcase
        Trixx::Application.log_attribute(:trixx_db_victim_user.to_s.upcase, config.trixx_db_victim_user)
      end
    when 'SQLITE' then
      config.trixx_db_user              = 'main'
      if Rails.env.test?
        config.trixx_db_victim_user     = 'main'  if Rails.env.test?
      end
    else
      raise "unsupported DB type '#{config.trixx_db_type}'"
    end


    Trixx::Application.set_and_log_attrib_from_env(:trixx_db_password)
    Trixx::Application.set_and_log_attrib_from_env(:trixx_db_query_timeout,                   default: 600, integer: true)
    Trixx::Application.set_and_log_attrib_from_env(:trixx_db_url,                             accept_empty: config.trixx_db_type == 'SQLITE')

    Trixx::Application.set_attrib_from_env(:trixx_db_user)
    config.trixx_db_user = config.trixx_db_user.upcase if config.trixx_db_type == 'ORACLE'
    Trixx::Application.log_attribute(:trixx_db_user.to_s.upcase, config.trixx_db_user)

    Trixx::Application.set_and_log_attrib_from_env(:trixx_error_max_retries,                  default: 5, integer: true, minimum: 1, maximum: 9999)
    Trixx::Application.set_and_log_attrib_from_env(:trixx_error_retry_start_delay,            default: 20, integer: true, minimum: 1)
    Trixx::Application.set_and_log_attrib_from_env(:trixx_info_contact_person,                accept_empty: true)
    Trixx::Application.set_and_log_attrib_from_env(:trixx_initial_worker_threads,             maximum: maximum_initial_worker_threads, integer: true, minimum: 0)
    Trixx::Application.set_and_log_attrib_from_env(:trixx_kafka_compression_codec,            default: 'gzip')
    supported_compression_codecs = ['none', 'snappy', 'gzip']
    raise "TRIXX_KAFKA_COMPRESSION_CODEC=#{config.trixx_kafka_compression_codec} not supported! Allowed values are: #{supported_compression_codecs}" if ! supported_compression_codecs.include? config.trixx_kafka_compression_codec
    Trixx::Application.set_and_log_attrib_from_env(:trixx_kafka_max_bulk_count,               default: 1000, integer: true, minimum: 1)
    Trixx::Application.set_and_log_attrib_from_env(:trixx_kafka_seed_broker,                  default: '/dev/null')
    Trixx::Application.set_and_log_attrib_from_env(:trixx_kafka_ssl_ca_cert,                  accept_empty: true)
    Trixx::Application.set_and_log_attrib_from_env(:trixx_kafka_ssl_client_cert,              accept_empty: true)
    Trixx::Application.set_and_log_attrib_from_env(:trixx_kafka_ssl_client_cert_key,          accept_empty: true)
    Trixx::Application.set_and_log_attrib_from_env(:trixx_kafka_ssl_client_cert_key_password, accept_empty: true)
    Trixx::Application.set_and_log_attrib_from_env(:trixx_kafka_total_buffer_size_mb,         default: 100,   integer: true, minimum: 1)
    Trixx::Application.set_and_log_attrib_from_env(:trixx_max_transaction_size,               default: 10000, integer: true, minimum: 1)
    Trixx::Application.set_and_log_attrib_from_env(:trixx_threads_for_api_requests,           default: 20, integer: true)  # Number of threads and DB-sessions in pool to reserve for API request handling and jobs

    # Puma allocates 7 internal threads + one thread per allowed connection in connection pool
    config.puma_internal_thread_limit = 10                                      # Number of threads to calculate for puma
    rails_max_thread_msg = "Should be set to greater than TRIXX_INITIAL_WORKER_THREADS (#{config.trixx_initial_worker_threads}) + #{config.trixx_threads_for_api_requests + config.puma_internal_thread_limit}!"
    raise "RAILS_MAX_THREADS not set! #{rails_max_thread_msg}" if ENV['RAILS_MAX_THREADS'].nil? && !Rails.env.test?
    if ENV['RAILS_MAX_THREADS'] && !Rails.env.test? && ENV['RAILS_MAX_THREADS'].to_i < (config.trixx_initial_worker_threads + config.trixx_threads_for_api_requests + config.puma_internal_thread_limit)
      raise "Environment variable RAILS_MAX_THREADS (#{ENV['RAILS_MAX_THREADS']}) is too low! #{rails_max_thread_msg}"
    end

    case config.trixx_db_type
    when 'ORACLE' then
      Trixx::Application.set_and_log_attrib_from_env(:tns_admin, accept_empty: true)
      if config.tns_admin
        System.setProperty("oracle.net.tns_admin", config.tns_admin)
      else
        raise "TNS_ADMIN must be set if TRIXX_DB_URL ('#{config.trixx_db_url}') is not a valid JDBC thin URL (host:port:sid or host:port/service_name) and is treated as TNS-alias" unless config.trixx_db_url[':']
      end
    end

    # check if database supports partitioning (possible and licensed)
    def partitioning
      if !defined? @trixx_db_partitioning
        @trixx_db_partitioning = case config.trixx_db_type
                                 when 'ORACLE' then
                                   Database.select_one("SELECT Value FROM v$Option WHERE Parameter='Partitioning'") == 'TRUE'
                                 else
                                   false
                                 end
        Rails.logger.info "Partitioning = #{@trixx_db_partitioning} for this #{config.trixx_db_type} database"
      end
      @trixx_db_partitioning
    end
  end
end
