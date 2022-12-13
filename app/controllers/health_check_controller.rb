require 'json'
class HealthCheckController < ApplicationController

  @@last_call_time = Time.now-100.seconds                                       # ensure enough distance at startup

  # GET /health_check
  # Does not require valid JWT
  # Should not contain internal secrets
  # called from outside like Docker health check
  def index
    jwt_validated = validate_jwt.nil?                                           # Does request has been called with valid JWT
    # Check for DOS on health check only if not called with valid JWT
    unless jwt_validated
      raise "Health check called too frequently" if Time.now - 1.seconds < @@last_call_time   # suppress DOS attacks
      @@last_call_time = Time.now
    end

    pretty_health_data, return_status = health_check_content(jwt_validated: jwt_validated)
    Rails.logger.info('HealthCheckController.index'){ pretty_health_data }
    render json: pretty_health_data, status: return_status
  end

  # GET /health_check/status
  # Called by frontend with valid JWT
  def status
    pretty_health_data, return_status = health_check_content(jwt_validated: true)
    render json: pretty_health_data, status: :ok
  end

  # GET /health_check/log_file
  def log_file
    send_file("#{Rails.root.join("log", Rails.env + ".log" )}", :filename => "#{Rails.env}.log")
  end


  # GET /health_check/config_info
  def config_info

    # array with info-hashes to display at home screen { name: xxx, value: yyy }
    info = []
    # info << { name: 'LOG_LEVEL: ',            value: KeyHelper.log_level_as_string}
    info << build_info_record(:cloudevents_source,                'Source info for CloudEvents header ce_source')
    info << build_info_record(:db_query_timeout,                  'Timeout for DB selections')
    info << build_info_record(:db_type,                           'Database type')
    info << build_info_record(:db_url,                            'Database URL')
    info << build_info_record(:db_user,                           'Database user for server operations')
    info << build_info_record(:error_max_retries,                 'Max. retries after transfer error')
    info << build_info_record(:error_retry_start_delay,           'Seconds after error before first retry starts. Tripled for each next retry.')
    info << build_info_record(:final_errors_keep_hours,           'Time before erasing')
    info << build_info_record(:info_contact_person,               'Name and email of contact person for display at GUI home screen')
    info << build_info_record(:initial_worker_threads,            'No. of workers for Kafka transfer')
    info << build_info_record(:kafka_compression_codec,           'Compression codec used to compress transferred events')
    info << build_info_record(:kafka_max_bulk_count,              'Max. messages in one call')
    info << build_info_record(:kafka_sasl_plain_username,         'Username for authentication with SASL')
    info << build_info_record(:kafka_ssl_ca_cert,                 'Path to CA certificate')
    info << build_info_record(:kafka_ssl_ca_certs_from_system,    'Use system CA certificates?')
    info << build_info_record(:kafka_ssl_client_cert,             'Path to client certificate')
    info << build_info_record(:kafka_ssl_client_cert_chain,       'Path to client certificate chain')
    info << build_info_record(:kafka_ssl_client_cert_key,         'Path to client key')
    info << build_info_record(:kafka_total_buffer_size_mb,        'Max. buffer size per thread')
    info << build_info_record(:kafka_seed_broker,                 '')
    info << build_info_record(:log_level,                         'Server side log level')
    info << build_info_record(:max_failed_logons_before_account_locked,  'Number of failed logons to GUI before the used user account will be locked')
    info << build_info_record(:max_partitions_to_count_as_healthy,  'Max. number of partitions, up to which the system is considered healthy')
    info << build_info_record(:max_transaction_size,              'Max. messages in a transaction')
    info << build_info_record(:max_simultaneous_table_initializations, '')
    info << build_info_record(:max_simultaneous_transactions,     'For insert in EVENT_LOGS')
    info << build_info_record(:max_worker_thread_sleep_time,      'Max. seconds an idle worker thread may sleep')
    info << build_info_record(:partition_interval,                'For table EVENT_LOGS')
    info << {
      name: 'RAILS_MAX_THREADS',
      description: 'max. number of threads for application',
      value: ENV['RAILS_MAX_THREADS'],
      default_value: 300,
      startup_config_value: ENV['RAILS_MAX_THREADS']
    }  # Default is set in Dockerfile
    info << build_info_record(:run_config,                        'Path to config file')
    info << build_info_record(:tz,                                'Local timezone within the Docker-container of the applikation')

    render json: { config_info: info  }, status: :ok
  end

  private
  # get Hash with health check and return code
  # @param [TrueClass, FalseClass] jwt_validated Is request called with valid JWT, then additional content becomes visible
  # @return [Hash, Symbol] Several health check info and status (:ok or :conflict)
  def health_check_content(jwt_validated:)
    memory_info_hash = ExceptionHelper.memory_info_hash
    health_data = {
      health_check_timestamp:       Time.now,
      build_version:                MovexCdc::Application.config.build_version,
      database_url:                 MovexCdc::Application.config.db_url,
      kafka_seed_broker:            MovexCdc::Application.config.kafka_seed_broker,
      start_working_timestamp:      ThreadHandling.get_instance.application_startup_timestamp,
      warnings:                     '',
      log_level:                    "#{KeyHelper.log_level_as_string} (#{Rails.logger.level})",
      memory:                       Hash[memory_info_hash.to_a.map{|a| [a[1][:name], a[1][:value]]}],
      kafka_max_bulk_count:         MovexCdc::Application.config.kafka_max_bulk_count,
      max_transaction_size:   MovexCdc::Application.config.max_transaction_size
    }

    begin
      if memory_info_hash[:available_memory][:value] / memory_info_hash[:total_memory][:value] < 0.1
        health_data[:warnings] << "\nAvailable memory is less than 10% of total memory! Risk of getting out of memory exists."
        health_data[:warnings] << "\nIncrease the memory for container or reduce either:"
        health_data[:warnings] << "\n- the number of threads (INITIAL_WORKER_THREADS)"
        health_data[:warnings] << "\n- the number of simultaneously processed records per transaction (MAX_TRANSACTION_SIZE) "
      end
    rescue Exception=>e
      health_data[:warnings] << "\nError calculating memory usage: #{e.class}:#{e.message}"
    end

    begin
      Rails.logger.debug('HealthCheckController.health_check_content') { "Start getting current thread count" }
      current_thread_count = ThreadHandling.get_instance.thread_count(raise_exception_if_locked: true)
      health_data[:current_number_of_worker_threads]  = current_thread_count
      if MovexCdc::Application.config.initial_worker_threads != current_thread_count
        health_data[:warnings] << "\nThread count = #{current_thread_count} but should be #{MovexCdc::Application.config.initial_worker_threads}"
      end
    rescue Exception=>e
      health_data[:warnings] << "\nError reading current_number_of_worker_threads: #{e.class}:#{e.message}"
    end

    health_data[:expected_number_of_worker_threads] = MovexCdc::Application.config.initial_worker_threads

    begin
      Rails.logger.debug('HealthCheckController.health_check_content') { "Start getting ThreadHandling.health_check_data" }
      health_data[:worker_threads] = ThreadHandling.get_instance.health_check_data(jwt_validated: jwt_validated)
    rescue Exception=>e
      health_data[:warnings] << "\nError reading worker_threads: #{e.class}:#{e.message}"
    end

    connection_info = []
    Rails.logger.debug('HealthCheckController.health_check_content') { "Start getting connection pool data" }
    connections = nil
    begin
      connections = ActiveRecord::Base.connection_pool.connections
    rescue ActiveRecord::ConnectionNotEstablished => e
      Rails.logger.warn "HealthCheckController.health_check_content: Error #{e.class}:#{e.message} at ActiveRecord::Base.connection_pool.connections! Doing retry."
      sleep 3                                                                   # Wait some time to fix sudden outage in access
      connections = ActiveRecord::Base.connection_pool.connections
    end
    connections.each do |conn|
      connection_info << {
        owner_thread: conn.owner&.object_id,
        owner_name:   conn.owner&.name,
        owner_status: conn.owner&.status,
        owner_alive:  conn.owner&.alive?,
        seconds_idle: conn.seconds_idle
      }
    end
    health_data[:connection_pool_stat] = ActiveRecord::Base.connection_pool.stat
    health_data[:connection_pool] = connection_info.sort_by {|c| "#{c[:owner_name]} #{c[:owner_thread]}" }

    Rails.logger.debug('HealthCheckController.health_check_content') { "Start getting thread list" }
    thread_info = []
    Thread.list.sort_by{|t| t.object_id}.each do |t|
      thread_state = {
        object_id:    t.object_id,
        name:         t.name,
        info:         t == Thread.current ? 'health_check request processing' : (t == Thread.main ? 'Application main thread' : ''),
        status:       t.status,
        alive:        t.alive?
      }
      thread_state[:stacktrace] = t&.backtrace if jwt_validated
      thread_info << thread_state
    end
    health_data[:number_of_threads] = thread_info.count
    health_data[:threads] = thread_info.sort_by {|t| t[:object_id] }


    begin
      Rails.logger.debug('HealthCheckController.health_check_content') { "Start getting TableInitialization.init_requests_count" }
      current_init_requests_count = TableInitialization.get_instance.init_requests_count(raise_exception_if_locked: true)
      health_data[:current_number_of_table_initialization_requests]  = current_init_requests_count
    rescue Exception=>e
      health_data[:warnings] << "\nError reading current_number_of_table_initialization_requests: #{e.class}:#{e.message}"
    end
    begin
      Rails.logger.debug('HealthCheckController.health_check_content') { "Start getting TableInitialization.health_check_data_requests" }
      health_data[:table_initialization_requests] = TableInitialization.get_instance.health_check_data_requests
    rescue Exception=>e
      health_data[:warnings] << "\nError reading table_initialization_requests: #{e.class}:#{e.message}"
    end

    begin
      Rails.logger.debug('HealthCheckController.health_check_content') { "Start getting TableInitialization.running_threads_count" }
      current_init_thread_count = TableInitialization.get_instance.running_threads_count(raise_exception_if_locked: true)
      health_data[:current_number_of_table_initialization_threads]  = current_init_thread_count
    rescue Exception=>e
      health_data[:warnings] << "\nError reading current_number_of_table_initialization_threads: #{e.class}:#{e.message}"
    end
    begin
      Rails.logger.debug('HealthCheckController.health_check_content') { "Start getting TableInitialization.health_check_data_threads" }
      health_data[:table_initialization_threads] = TableInitialization.get_instance.health_check_data_threads(jwt_validated: jwt_validated)
    rescue Exception=>e
      health_data[:warnings] << "\nError reading table_initialization_threads: #{e.class}:#{e.message}"
    end

    # get health status of last job executions
    begin
      health_data[:warnings] << ApplicationJob.last_job_warnings(SystemValidationJob)
      health_data[:warnings] << ApplicationJob.last_job_warnings(HourlyJob)
      health_data[:warnings] << ApplicationJob.last_job_warnings(DailyJob)
      health_data[:job_info] = ApplicationJob.job_infos
      # Sometimes at OutOfMemory conditions jobs are not restarted and remain inactive for the future
      # Housekeeping executed by Docker container can repair this seldom scenario
      ApplicationJob.ensure_job_rescheduling
    rescue Exception=>e
      health_data[:warnings] << "\nError reading job states: #{e.class}:#{e.message}"
    end

    # get status of event queue
    begin
      partition_threshold = MovexCdc::Application.config.max_partitions_to_count_as_healthy
      health_data[:event_log_status] = EventLog.health_check_status
      if health_data[:event_log_status][:used_partition_count] && health_data[:event_log_status][:used_partition_count] > partition_threshold
        health_data[:warnings] << "\n:Partition count (#{health_data[:event_log_status][:used_partition_count]}) exceeds threshold (#{partition_threshold})"
      end
    rescue Exception=>e
      health_data[:warnings] << "\nError reading event queue states: #{e.class}:#{e.message}"
    end

    pretty_health_data = JSON.pretty_generate(health_data)

    return pretty_health_data, health_data[:warnings] == '' ? :ok : :conflict
  end

  # Build a record for config_info
  # key should be lower case
  def build_info_record(key, description)
    info_record = { name: key.upcase, description: description, value:nil, default_value: nil, startup_config_value: nil }
    info_record[:value] = MovexCdc::Application.config.send(key) if MovexCdc::Application.config.respond_to?(key)
    config_info = MovexCdc::Application.config_attributes(key)
    if config_info
      info_record[:default_value]         = config_info[:default_value]
      info_record[:startup_config_value]  = config_info[:startup_config_value]
    end
    info_record
  end
end
