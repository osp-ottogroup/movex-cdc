require 'json'
class HealthCheckController < ApplicationController

  @@last_call_time = Time.now-100.seconds                                       # ensure enough distance at startup

  # GET /health_check
  # Does not require valid JWT
  # Should not contain internal secrets
  # called from outside like Docker health check
  def index
    raise "Health check called too frequently" if Time.now - 1.seconds < @@last_call_time   # suppress DOS attacks
    @@last_call_time = Time.now

    pretty_health_data, return_status = health_check_content
    Rails.logger.info(pretty_health_data)
    render json: pretty_health_data, status: return_status
  end

  # GET /health_check/status
  # Called by frontend with valid JWT
  def status
    pretty_health_data, return_status = health_check_content
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
    info << { name: 'LOG_LEVEL: server side log level',                           value: KeyHelper.log_level_as_string}
    info << { name: 'RAILS_MAX_THREADS: max. number of threads for application',  value: ENV['RAILS_MAX_THREADS']}
    info << { name: 'TRIXX_DB_QUERY_TIMEOUT: Timeout for DB selections',          value: Trixx::Application.config.trixx_db_query_timeout}
    info << { name: 'TRIXX_DB_TYPE: Database type',                               value: Trixx::Application.config.trixx_db_type}
    info << { name: 'TRIXX_DB_URL: Database URL',                                 value: Trixx::Application.config.trixx_db_url}
    info << { name: 'TRIXX_DB_USER: Database user for server operations',         value: Trixx::Application.config.trixx_db_user}
    info << { name: 'TRIXX_ERROR_MAX_RETRIES: Max. retries after transfer error', value: Trixx::Application.config.trixx_error_max_retries}
    info << { name: 'TRIXX_ERROR_RETRY_START_DELAY: Initial delay after error',   value: Trixx::Application.config.trixx_error_max_retries}
    info << { name: 'TRIXX_FINAL_ERRORS_KEEP_HOURS: Time before erasing',         value: Trixx::Application.config.trixx_final_errors_keep_hours}
    info << { name: 'TRIXX_INFO_CONTACT_PERSON',                                  value: Trixx::Application.config.trixx_info_contact_person }
    info << { name: 'TRIXX_INITIAL_WORKER_THREADS: no. of workers for Kafka transfer', value: Trixx::Application.config.trixx_initial_worker_threads }
    info << { name: 'TRIXX_KAFKA_COMPRESSION_CODEC',                              value: Trixx::Application.config.trixx_kafka_compression_codec}
    info << { name: 'TRIXX_KAFKA_MAX_BULK_COUNT: max. messages in one call',      value: Trixx::Application.config.trixx_kafka_max_bulk_count}
    info << { name: 'TRIXX_KAFKA_SSL_CA_CERT: path to CA certificate',            value: Trixx::Application.config.trixx_kafka_ssl_ca_cert}
    info << { name: 'TRIXX_KAFKA_SSL_CLIENT_CERT: path to client certificate',    value: Trixx::Application.config.trixx_kafka_ssl_client_cert}
    info << { name: 'TRIXX_KAFKA_SSL_CLIENT_CERT_KEY: path to client key',        value: Trixx::Application.config.trixx_kafka_ssl_client_cert_key}
    info << { name: 'TRIXX_KAFKA_TOTAL_BUFFER_SIZE_MB: max. buffer size per thread', value: Trixx::Application.config.trixx_kafka_total_buffer_size_mb}
    info << { name: 'TRIXX_KAFKA_SEED_BROKER',                                    value: Trixx::Application.config.trixx_kafka_seed_broker}
    info << { name: 'TRIXX_MAX_TRANSACTION_SIZE: max. messages in a transaction', value: Trixx::Application.config.trixx_max_transaction_size}
    info << { name: 'TRIXX_MAX_SIMULTANEOUS_TABLE_INITIALIZATIONS',               value: Trixx::Application.config.trixx_max_simultaneous_table_initializations}
    info << { name: 'TRIXX_MAX_SIMULTANEOUS_TRANSACTIONS: for insert in EVENT_LOGS',  value: Trixx::Application.config.trixx_max_simultaneous_transactions}
    info << { name: 'TRIXX_RUN_CONFIG: path to config file',                      value: Trixx::Application.config.trixx_run_config}
    info << { name: 'TRIXX_PARTITION_INTERVAL: for table EVENT_LOGS',             value: Trixx::Application.config.trixx_partition_interval}

    render json: { config_info: info  }, status: :ok
  end

  private
  # get Hash with health check and return code
  def health_check_content
    memory_info_hash = ExceptionHelper.memory_info_hash
    health_data = {
      health_check_timestamp:       Time.now,
      build_version:                'unknown',
      database_url:                 Trixx::Application.config.trixx_db_url,
      kafka_seed_broker:            Trixx::Application.config.trixx_kafka_seed_broker,
      start_working_timestamp:      ThreadHandling.get_instance.application_startup_timestamp,
      warnings:                     '',
      log_level:                    "#{KeyHelper.log_level_as_string} (#{Rails.logger.level})",
      memory:                       Hash[memory_info_hash.to_a.map{|a| [a[1][:name], a[1][:value]]}],
      trixx_kafka_max_bulk_count:   Trixx::Application.config.trixx_kafka_max_bulk_count
    }

    begin
      health_data[:build_version] = File.read(Rails.root.join('build_version'))
    rescue Errno::ENOENT
      health_data[:build_version] = 'File ./build_version does not exist'
    end

    begin
      if memory_info_hash[:available_memory][:value] / memory_info_hash[:total_memory][:value] < 0.1
        health_data[:warnings] << "\nAvailable memory is less than 10% of total memory! Risk of getting out of memory exists."
        health_data[:warnings] << "\nIncrease the memory for container or reduce either:"
        health_data[:warnings] << "\n- the number of threads (TRIXX_INITIAL_WORKER_THREADS)"
        health_data[:warnings] << "\n- the number of simultaneously processed records per transaction (TRIXX_MAX_TRANSACTION_SIZE) "
      end
    rescue Exception=>e
      health_data[:warnings] << "\nError calculating memory usage: #{e.class}:#{e.message}"
    end

    begin
      Rails.logger.debug "HealthCheckController.index: Start getting current thread count"
      current_thread_count = ThreadHandling.get_instance.thread_count(raise_exception_if_locked: true)
      health_data[:current_number_of_worker_threads]  = current_thread_count
      if Trixx::Application.config.trixx_initial_worker_threads != current_thread_count
        health_data[:warnings] << "\nThread count = #{current_thread_count} but should be #{Trixx::Application.config.trixx_initial_worker_threads}"
      end
    rescue Exception=>e
      health_data[:warnings] << "\nError reading current_number_of_worker_threads: #{e.class}:#{e.message}"
    end

    health_data[:expected_number_of_worker_threads] = Trixx::Application.config.trixx_initial_worker_threads

    begin
      Rails.logger.debug "HealthCheckController.index: Start getting ThreadHandling.health_check_data"
      health_data[:worker_threads] = ThreadHandling.get_instance.health_check_data
    rescue Exception=>e
      health_data[:warnings] << "\nError reading worker_threads: #{e.class}:#{e.message}"
    end

    connection_info = []
    Rails.logger.debug "HealthCheckController.index: Start getting connection pool data"
    ActiveRecord::Base.connection_pool.connections.each do |conn|
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

    Rails.logger.debug "HealthCheckController.index: Start getting thread list"
    thread_info = []
    Thread.list.each do |t|
      thread_info << {
        object_id:    t.object_id,
        name:         t.name,
        info:         t == Thread.current ? 'health_check request processing' : (t == Thread.main ? 'Application main thread' : ''),
        status:       t.status,
        alive:        t.alive?
      }
    end
    health_data[:number_of_threads] = thread_info.count
    health_data[:threads] = thread_info.sort_by {|t| t[:object_id] }


    begin
      Rails.logger.debug "HealthCheckController.index: Start getting TableInitialization.init_requests_count"
      current_init_requests_count = TableInitialization.get_instance.init_requests_count(raise_exception_if_locked: true)
      health_data[:current_number_of_table_initialization_requests]  = current_init_requests_count
    rescue Exception=>e
      health_data[:warnings] << "\nError reading current_number_of_table_initialization_requests: #{e.class}:#{e.message}"
    end
    begin
      Rails.logger.debug "HealthCheckController.index: Start getting TableInitialization.health_check_data_requests"
      health_data[:table_initialization_requests] = TableInitialization.get_instance.health_check_data_requests
    rescue Exception=>e
      health_data[:warnings] << "\nError reading table_initialization_requests: #{e.class}:#{e.message}"
    end

    begin
      Rails.logger.debug "HealthCheckController.index: Start getting TableInitialization.running_threads_count"
      current_init_thread_count = TableInitialization.get_instance.running_threads_count(raise_exception_if_locked: true)
      health_data[:current_number_of_table_initialization_threads]  = current_init_thread_count
    rescue Exception=>e
      health_data[:warnings] << "\nError reading current_number_of_table_initialization_threads: #{e.class}:#{e.message}"
    end
    begin
      Rails.logger.debug "HealthCheckController.index: Start getting TableInitialization.health_check_data_threads"
      health_data[:table_initialization_threads] = TableInitialization.get_instance.health_check_data_threads
    rescue Exception=>e
      health_data[:warnings] << "\nError reading table_initialization_threads: #{e.class}:#{e.message}"
    end

    # get health status of last job executions
    begin
      health_data[:warnings] << ApplicationJob.last_job_warnings(SystemValidationJob)
      health_data[:warnings] << ApplicationJob.last_job_warnings(HourlyJob)
      health_data[:warnings] << ApplicationJob.last_job_warnings(DailyJob)
      health_data[:job_info] = ApplicationJob.job_infos
    rescue Exception=>e
      health_data[:warnings] << "\nError reading job states: #{e.class}:#{e.message}"
    end

    # get status of event queue
    begin
      health_data[:event_log_status] = EventLog.health_check_status
    rescue Exception=>e
      health_data[:warnings] << "\nError reading event queue states: #{e.class}:#{e.message}"
    end

    pretty_health_data = JSON.pretty_generate(health_data)

    return pretty_health_data, health_data[:warnings] == '' ? :ok : :conflict
  end
end
