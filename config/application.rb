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
require 'socket'


# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module MovexCdc
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

    # Ensure that values stored in DB in the same timezone as the application uses
    config.active_record.default_timezone = :local

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

    # Hash with MOVEX CDC's configs config_name: { default_value:, startup_config_value:}
    @@config_attributes = {}
    def self.config_attributes(key)
      @@config_attributes[key]
    end

    def self.maximum_initial_worker_threads
      retval = nil                                                              # No limit as default
      retval = 1 if config.db_type == 'SQLITE'
      retval
    end

    # Log a configuration attribute
    # @param key [String] Name of configuration attribute, should be upper case
    # @param value [String] Value of configuration attribute
    # @return [void]
    def self.log_attribute(key, value)
      return if value.nil? || value == ''
      if key['PASSWORD']
        outval = '*****'
      else
        outval = value
      end
      puts "#{key.ljust(40, ' ')} #{outval}"
    end

    # Set the value of a configuration attribute from environment variable if it exists, otherwise from config file
    # @param key [Symbol] Name of configuration attribute
    # @param options [Hash] Options for setting the configuration attribute [:default, :upcase, :downcase, :integer, :maximum, :minimum, :accept_empty]
    # @return [String] The value of the configuration attribute to be used as log output
    def self.set_attrib_from_env(key, options={})
      up_key = key.to_s.upcase
      value = options[:default]
      value = MovexCdc::Application.config.send(key) if MovexCdc::Application.config.respond_to?(key) # Value already set by config file
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
      MovexCdc::Application.config.send("#{key}=", value)                          # ensure all config methods are defined whether with values or without
      @@config_attributes[key] = {} unless @@config_attributes.has_key?(key)    # records from config file may already exist
      @@config_attributes[key][:default_value]        = options[:default]
      @@config_attributes[key][:startup_config_value] = value if ENV[up_key]    # remember startup config only if set explicitely by environment

      raise "Missing configuration value for '#{up_key}'! Aborting..." if !options[:accept_empty] && MovexCdc::Application.config.send(key).nil?
      log_value
    end

    def self.set_and_log_attrib_from_env(key, options={})
      MovexCdc::Application.log_attribute(key.to_s.upcase, set_attrib_from_env(key, options))
    end

    puts "\nStarting MOVEX Change Data Capture application at #{Time.now}\n"

    puts "Configuration attributes (if defined):"
    MovexCdc::Application.log_attribute('RAILS_ENV', Rails.env)
    MovexCdc::Application.log_attribute('RAILS_MAX_THREADS', ENV['RAILS_MAX_THREADS'])

    # Load configuration file, should always exist, at leastwith default values
    config.run_config = "#{Rails.root}/config/run_config.yml"                   # Default
    config.run_config = ENV['RUN_CONFIG'] if ENV['RUN_CONFIG'] && ENV['RUN_CONFIG'] != ''
    MovexCdc::Application.log_attribute('RUN_CONFIG', config.run_config)
    run_config = YAML.load_file(config.run_config)
    run_config = {} unless run_config                                           # returns false for a file without content
    raise "Unable to load and parse file #{config.run_config}! Content of class #{run_config.class}:\n#{run_config}" if run_config.class != Hash
    run_config.each do |key, value|
      config.send "#{key.downcase}=", value                                     # copy file content to config at first
      @@config_attributes[key.downcase.to_sym] = {default_value: nil, startup_config_value: value} # Default value is set later
    end
    MovexCdc::Application.set_and_log_attrib_from_env(:log_level, downcase: true, default: (Rails.env.production? ? :info : :debug))
    config.log_level = config.log_level.to_sym if config.log_level && config.log_level.class == String

    MovexCdc::Application.set_and_log_attrib_from_env(:db_type, upcase: true)

    supported_db_types = ['ORACLE', 'SQLITE']
    raise "Unsupported value '#{config.db_type}' for configuration attribute 'DB_TYPE'! Supported values are #{supported_db_types}" unless supported_db_types.include?(config.db_type)

    if Rails.env.test?
      MovexCdc::Application.set_attrib_from_env(:db_password, default: 'tjskfs88323#HDG3')
      MovexCdc::Application.set_attrib_from_env(:db_victim_password, default: 'ksfaaH#Elcf2342')
    end

    case config.db_type
    when 'ORACLE' then
      MovexCdc::Application.set_and_log_attrib_from_env(:db_sys_user, default: 'sys', accept_empty: !Rails.env.test?) if MovexCdc::Application.config.respond_to?(:db_sys_user) || ENV['DB_SYS_USER']
      MovexCdc::Application.set_and_log_attrib_from_env(:db_sys_password, default: 'oracle', accept_empty: !Rails.env.test?) if MovexCdc::Application.config.respond_to?(:db_sys_password) || ENV['DB_SYS_PASSWORD']
      if Rails.env.test?                                                        # prevent test-user from overwriting development or production structures in DB
        config.db_user            = "test_#{config.respond_to?(:db_user) ? config.db_user : 'movex_cdc'}"
        MovexCdc::Application.set_attrib_from_env(:db_victim_user, default: 'movex_cdc_victim')
        config.db_victim_user = config.db_victim_user.upcase
        MovexCdc::Application.log_attribute(:db_victim_user.to_s.upcase, config.db_victim_user)
      end
    when 'SQLITE' then
      config.db_user                = 'main'
      if Rails.env.test?
        config.db_victim_user       = 'main'
      end
    else
      raise "unsupported DB type '#{config.db_type}'"
    end

    build_version = ''
    begin
      build_version = File.read(Rails.root.join('build_version'))&.delete("\n")
    rescue Errno::ENOENT
      build_version = 'File ./build_version does not exist'
    end

    MovexCdc::Application.set_and_log_attrib_from_env(:build_version, default: build_version)
    MovexCdc::Application.set_and_log_attrib_from_env(:cloudevents_source, default: "MOVEX-CDC-#{Socket.gethostname}")
    MovexCdc::Application.set_and_log_attrib_from_env(:db_password)
    MovexCdc::Application.set_and_log_attrib_from_env(:db_query_timeout, default: 600, integer: true)
    MovexCdc::Application.set_and_log_attrib_from_env(:db_url, accept_empty: config.db_type == 'SQLITE')

    MovexCdc::Application.set_attrib_from_env(:db_user)
    config.db_user = config.db_user.upcase if config.db_type == 'ORACLE'
    MovexCdc::Application.log_attribute(:db_user.to_s.upcase, config.db_user)

    MovexCdc::Application.set_and_log_attrib_from_env(:error_max_retries, default: 5, integer: true, minimum: 1, maximum: 9999)
    MovexCdc::Application.set_and_log_attrib_from_env(:error_retry_start_delay, default: 20, integer: true, minimum: 1)
    MovexCdc::Application.set_and_log_attrib_from_env(:final_errors_keep_hours, default: 240, integer: true, minimum: 1)
    MovexCdc::Application.set_and_log_attrib_from_env(:info_contact_person, accept_empty: true)
    MovexCdc::Application.set_and_log_attrib_from_env(:initial_worker_threads, default: 3, maximum: maximum_initial_worker_threads, integer: true, minimum: 0)
    MovexCdc::Application.set_and_log_attrib_from_env(:kafka_client_library, default: 'java')
    MovexCdc::Application.set_and_log_attrib_from_env(:kafka_compression_codec, default: 'gzip')
    supported_compression_codecs = ['none', 'snappy', 'gzip', 'lz4', 'zstd']
    raise "KAFKA_COMPRESSION_CODEC=#{config.kafka_compression_codec} not supported! Allowed values are: #{supported_compression_codecs}" if ! supported_compression_codecs.include? config.kafka_compression_codec
    MovexCdc::Application.set_and_log_attrib_from_env(:kafka_max_bulk_count, default: 1000, integer: true, minimum: 1)
    MovexCdc::Application.set_and_log_attrib_from_env(:kafka_properties_file, accept_empty: true)
    MovexCdc::Application.set_and_log_attrib_from_env(:kafka_seed_broker, default: '<not specified>')
    MovexCdc::Application.set_and_log_attrib_from_env(:kafka_sasl_plain_password, accept_empty: true)
    MovexCdc::Application.set_and_log_attrib_from_env(:kafka_sasl_plain_username, accept_empty: true)
    MovexCdc::Application.set_and_log_attrib_from_env(:kafka_security_protocol, accept_empty: true)
    MovexCdc::Application.set_and_log_attrib_from_env(:kafka_ssl_ca_cert, accept_empty: true)
    MovexCdc::Application.set_and_log_attrib_from_env(:kafka_ssl_client_cert_chain, accept_empty: true)
    MovexCdc::Application.set_and_log_attrib_from_env(:kafka_ssl_ca_certs_from_system, accept_empty: true)  # nil defaults to false
    MovexCdc::Application.set_and_log_attrib_from_env(:kafka_ssl_client_cert, accept_empty: true)
    MovexCdc::Application.set_and_log_attrib_from_env(:kafka_ssl_client_cert_key, accept_empty: true)
    MovexCdc::Application.set_and_log_attrib_from_env(:kafka_ssl_client_cert_key_password, accept_empty: true) # deprecated, use kafka_ssl_key_password instead
    if config.kafka_ssl_client_cert_key_password
      puts "WARNING: KAFKA_SSL_CLIENT_CERT_KEY_PASSWORD is deprecated, use KAFKA_SSL_KEY_PASSWORD instead for configuration"
    end
    MovexCdc::Application.set_and_log_attrib_from_env(:kafka_ssl_keystore_location, accept_empty: true)
    MovexCdc::Application.set_and_log_attrib_from_env(:kafka_ssl_keystore_password, accept_empty: true)
    MovexCdc::Application.set_and_log_attrib_from_env(:kafka_ssl_keystore_type, accept_empty: true)
    MovexCdc::Application.set_and_log_attrib_from_env(:kafka_ssl_key_password, accept_empty: true, default: config.kafka_ssl_client_cert_key_password) # Use deprecated config as default
    MovexCdc::Application.set_and_log_attrib_from_env(:kafka_ssl_truststore_location, accept_empty: true)
    MovexCdc::Application.set_and_log_attrib_from_env(:kafka_ssl_truststore_password, accept_empty: true)
    MovexCdc::Application.set_and_log_attrib_from_env(:kafka_ssl_truststore_type, accept_empty: true)
    MovexCdc::Application.set_and_log_attrib_from_env(:kafka_total_buffer_size_mb, default: 100, integer: true, minimum: 1)
    MovexCdc::Application.set_and_log_attrib_from_env(:max_failed_logons_before_account_locked, default: 3, integer: true, minimum: 0, maximum:99)
    MovexCdc::Application.set_and_log_attrib_from_env(:max_partitions_to_count_as_healthy, default: 15, integer: true, minimum: 1)
    MovexCdc::Application.set_and_log_attrib_from_env(:max_simultaneous_table_initializations, default: 5, integer: true, minimum: 1)
    MovexCdc::Application.set_and_log_attrib_from_env(:max_simultaneous_transactions, default: 60, integer: true, minimum: 1)
    MovexCdc::Application.set_and_log_attrib_from_env(:max_transaction_size, default: 10000, integer: true, minimum: 1)
    MovexCdc::Application.set_and_log_attrib_from_env(:max_worker_thread_sleep_time, default: 60, integer: true, minimum: 1)
    MovexCdc::Application.set_and_log_attrib_from_env(:partition_interval, default: 60, integer: true, minimum: 1, maximum: 6000000)
    MovexCdc::Application.set_and_log_attrib_from_env(:threads_for_api_requests, default: 20, integer: true)  # Number of threads and DB-sessions in pool to reserve for API request handling and jobs

    # Puma allocates 7 internal threads + one thread per allowed connection in connection pool
    config.puma_internal_thread_limit = 10                                      # Number of threads to calculate for puma
    rails_max_thread_msg = "Should be set to greater than INITIAL_WORKER_THREADS (#{config.initial_worker_threads}) + #{config.threads_for_api_requests + config.puma_internal_thread_limit}!"
    raise "RAILS_MAX_THREADS not set! #{rails_max_thread_msg}" if ENV['RAILS_MAX_THREADS'].nil? && !Rails.env.test?
    if ENV['RAILS_MAX_THREADS'] && !Rails.env.test? && ENV['RAILS_MAX_THREADS'].to_i < (config.initial_worker_threads + config.threads_for_api_requests + config.puma_internal_thread_limit)
      raise "Environment variable RAILS_MAX_THREADS (#{ENV['RAILS_MAX_THREADS']}) is too low! #{rails_max_thread_msg}"
    end

    case config.db_type
    when 'ORACLE' then
      MovexCdc::Application.set_and_log_attrib_from_env(:tns_admin, accept_empty: true)
      if config.tns_admin
        System.setProperty("oracle.net.tns_admin", config.tns_admin)
        raise "No file tnsnames.ora found at '#{config.tns_admin}'! Unset environment value TNS_ADMIN if you don't want to use it." unless File.file?(File.join(config.tns_admin, 'tnsnames.ora'))
      else
        raise "TNS_ADMIN must be set if DB_URL ('#{config.db_url}') is not a valid JDBC thin URL (host:port:sid or host:port/service_name) and is treated as TNS-alias" unless config.db_url[':']
      end
    end

    # check if database supports partitioning (possible and licensed)
    def partitioning?
      if !defined? @db_partitioning
        @db_partitioning = case config.db_type
                                 when 'ORACLE' then
                                   Database.select_one("SELECT Value FROM v$Option WHERE Parameter='Partitioning'") == 'TRUE'
                                 else
                                   false
                                 end
        Rails.logger.info('Application'){ "Partitioning = #{@db_partitioning} for this #{config.db_type} database" }
      end
      @db_partitioning
    end
  end
end
