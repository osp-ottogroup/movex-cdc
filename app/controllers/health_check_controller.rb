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
    # info << { name: 'LOG_LEVEL: ',            value: KeyHelper.log_level_as_string}
    info << build_info_record(:log_level,                         'server side log level')
    info << { name: 'RAILS_MAX_THREADS: max. number of threads for application',  value: ENV['RAILS_MAX_THREADS'], default_value: 300, startup_config_value: ENV['RAILS_MAX_THREADS']}  # Default is set in Dockerfile
    info << build_info_record(:trixx_db_query_timeout,            'Timeout for DB selections')
    info << build_info_record(:trixx_db_type,                     'Database type')
    info << build_info_record(:trixx_db_url,                      'Database URL')
    info << build_info_record(:trixx_db_user,                     'Database user for server operations')
    info << build_info_record(:trixx_error_max_retries,           'Max. retries after transfer error')
    info << build_info_record(:trixx_error_max_retry_start_delay, 'Initial delay after error')
    info << build_info_record(:trixx_final_errors_keep_hours,     'Time before erasing')
    info << build_info_record(:trixx_info_contact_person,         '')
    info << build_info_record(:trixx_initial_worker_threads,      'no. of workers for Kafka transfer')
    info << build_info_record(:trixx_kafka_compression_codec,     '')
    info << build_info_record(:trixx_kafka_max_bulk_count,        'max. messages in one call')
    info << build_info_record(:trixx_kafka_ssl_ca_cert,           'path to CA certificate')
    info << build_info_record(:trixx_kafka_ssl_client_cert,       'path to client certificate')
    info << build_info_record(:trixx_kafka_ssl_client_cert_key,   'path to client key')
    info << build_info_record(:trixx_kafka_total_buffer_size_mb,  'max. buffer size per thread')
    info << build_info_record(:trixx_kafka_seed_broker,           '')
    info << build_info_record(:trixx_max_transaction_size,        'max. messages in a transaction')
    info << build_info_record(:trixx_max_simultaneous_table_initializations, '')
    info << build_info_record(:trixx_max_simultaneous_transactions, 'for insert in EVENT_LOGS')
    info << build_info_record(:trixx_run_config,                  'path to config file')
    info << build_info_record(:trixx_partition_interval,          'for table EVENT_LOGS')

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
      # Sometimes at OutOfMemory conditions jobs are not restarted and remain inactive for the future
      # Housekeeping executed by Docker container can repair this seldom scenario
      ApplicationJob.ensure_job_rescheduling
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

  # Build a record for config_info
  # key should be lower case
  def build_info_record(key, description)
    info_record = { name: "#{key.upcase}: #{description}", value:nil, default_value: nil, startup_config_value: nil }
    info_record[:value] = Trixx::Application.config.send(key) if Trixx::Application.config.respond_to?(key)
    config_info = Trixx::Application.config_attributes(key)
    if config_info
      info_record[:default_value]         = config_info[:default_value]
      info_record[:startup_config_value]  = config_info[:startup_config_value]
    end
    info_record
  end
end
