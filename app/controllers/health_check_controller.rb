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
    build_info_record(info, :cloudevents_source,                'Source info for CloudEvents header ce_source')
    build_info_record(info, :db_query_timeout,                  'Timeout for DB selections')
    build_info_record(info, :db_type,                           'Database type')
    build_info_record(info, :db_url,                            'Database URL')
    build_info_record(info, :db_user,                           'Database user for server operations')
    build_info_record(info, :error_max_retries,                 'Max. retries after transfer error')
    build_info_record(info, :error_retry_start_delay,           'Seconds after error before first retry starts. Tripled for each next retry.')
    build_info_record(info, :final_errors_keep_hours,           'Time before erasing')
    build_info_record(info, :info_contact_person,               'Name and email of contact person for display at GUI home screen')
    build_info_record(info, :initial_worker_threads,            'No. of workers for Kafka transfer')
    build_info_record(info, :kafka_compression_codec,           'Compression codec used to compress transferred events')
    build_info_record(info, :kafka_producer_timeout,            'Timeout in milliseconds for Kafka producer to wait for response of broker (max.block.ms)')
    build_info_record(info, :kafka_sasl_plain_username,         'Username for authentication with SASL')
    build_info_record(info, :kafka_seed_broker,                 'Comma-separated list of seed-brokers for Kafka logon')
    build_info_record(info, :kafka_security_protocol,           'Security protocol for Kafka connection')
    build_info_record(info, :kafka_ssl_ca_cert,                 'Path to CA certificate')
    build_info_record(info, :kafka_ssl_ca_certs_from_system,    'Use system CA certificates?')
    build_info_record(info, :kafka_ssl_client_cert,             'Path to client certificate')
    build_info_record(info, :kafka_ssl_client_cert_chain,       'Path to client certificate chain')
    build_info_record(info, :kafka_ssl_client_cert_key,         'Path to client key')
    build_info_record(info, :kafka_ssl_keystore_location,       'Path to keystore file in JKS format')
    build_info_record(info, :kafka_ssl_keystore_type,           'Type of keystore file')
    build_info_record(info, :kafka_ssl_truststore_location,     'Path to truststore file in JKS format')
    build_info_record(info, :kafka_ssl_truststore_type,         'Type of truststore file')
    build_info_record(info, :kafka_total_buffer_size_mb,        'Max. buffer size per thread')
    build_info_record(info, :kafka_transaction_timeout,         'Max. duration in milliseconds of a Kafka transaction')
    build_info_record(info, :legacy_ts_format,                  'Keep unusualtimestamp format of previous releases')
    build_info_record(info, :log_level,                         'Server side log level')
    build_info_record(info, :max_failed_logons_before_account_locked,  'Number of failed logons to GUI before the used user account will be locked')
    build_info_record(info, :max_partitions_to_count_as_healthy,  'Max. number of partitions, up to which the system is considered healthy')
    build_info_record(info, :max_transaction_size,              'Max. messages in a single transaction')
    build_info_record(info, :max_simultaneous_table_initializations, '')
    build_info_record(info, :max_simultaneous_transactions,     'For insert in EVENT_LOGS')
    build_info_record(info, :max_worker_thread_sleep_time,      'Max. seconds an idle worker thread may sleep')
    build_info_record(info, :partition_interval,                'For table EVENT_LOGS')
    info << {
      name: 'RAILS_MAX_THREADS',
      description: 'max. number of threads for application',
      value: ENV['RAILS_MAX_THREADS'],
      default_value: 300,
      startup_config_value: ENV['RAILS_MAX_THREADS']
    }  # Default is set in Dockerfile
    build_info_record(info, :run_config,                        'Path to config file')
    build_info_record(info, :tz,                                'Local timezone within the Docker-container of the applikation')

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
      garbage_collector:            garbage_collector_info,
      max_transaction_size:   MovexCdc::Application.config.max_transaction_size
    }

    begin
      if memory_info_hash[:available_memory][:value] / memory_info_hash[:total_memory][:value] < 0.1
        health_data[:warnings] << "\nAvailable memory (#{memory_info_hash[:available_memory][:value]} G) is less than 10% of total memory (#{memory_info_hash[:total_memory][:value]} G)! Risk of getting out of memory exists."
        health_data[:warnings] << "\nIncrease the memory for container or reduce either:"
        health_data[:warnings] << "\n- the number of threads (INITIAL_WORKER_THREADS)"
        health_data[:warnings] << "\n- the number of simultaneously processed records per transaction (MAX_TRANSACTION_SIZE) "
      end
      if memory_info_hash[:used_java_heap][:value] / memory_info_hash[:maximum_java_heap][:value] > 0.9
        health_data[:warnings] << "\nUsed Java heap size (#{memory_info_hash[:used_java_heap][:value]} G) exceededs more than 90% of maximum java heap size (#{memory_info_hash[:maximum_java_heap][:value]} G)! Risk of getting out of memory in Java exists."
        health_data[:warnings] << "\nIncrease the setting for JAVAOPTS e.g. to '-Xmx3072m' or reduce either:"
        health_data[:warnings] << "\n- the number of threads (INITIAL_WORKER_THREADS)"
        health_data[:warnings] << "\n- the number of simultaneously processed records per transaction (MAX_TRANSACTION_SIZE) "
      end
    rescue Exception=>e
      ExceptionHelper.log_exception(e, 'HealthCheckController.health_check_content', additional_msg: "Error calculating memory usage")
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
      ExceptionHelper.log_exception(e, 'HealthCheckController.health_check_content', additional_msg: "Error reading current_number_of_worker_threads")
      health_data[:warnings] << "\nError reading current_number_of_worker_threads: #{e.class}:#{e.message}"
    end

    health_data[:expected_number_of_worker_threads] = MovexCdc::Application.config.initial_worker_threads

    begin
      Rails.logger.debug('HealthCheckController.health_check_content') { "Start getting ThreadHandling.health_check_data" }
      health_data[:worker_threads] = ThreadHandling.get_instance.health_check_data(jwt_validated: jwt_validated)
      health_data[:worker_threads].each do |worker_state|
        health_data[:warnings] << "\nWorker ID=#{worker_state[:worker_id]} thread=#{worker_state[:thread_id]}: #{worker_state[:warning]} " if worker_state[:warning] != ''
      end
    rescue Exception=>e
      ExceptionHelper.log_exception(e, 'HealthCheckController.health_check_content', additional_msg: "Error reading worker_threads")
      health_data[:warnings] << "\nError reading worker_threads: #{e.class}:#{e.message}"
    end

    connection_info = []
    Rails.logger.debug('HealthCheckController.health_check_content') { "Start getting connection pool data" }
    connections = nil
    begin
      connections = ActiveRecord::Base.connection_pool.connections
    rescue ActiveRecord::ConnectionNotEstablished => e
      Rails.logger.warn("HealthCheckController.health_check_content") { "Error #{e.class}:#{e.message} at ActiveRecord::Base.connection_pool.connections! Doing retry." }
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
      ExceptionHelper.log_exception(e, 'HealthCheckController.health_check_content', additional_msg: "Error reading current_number_of_table_initialization_requests")
      health_data[:warnings] << "\nError reading current_number_of_table_initialization_requests: #{e.class}:#{e.message}"
    end
    begin
      Rails.logger.debug('HealthCheckController.health_check_content') { "Start getting TableInitialization.health_check_data_requests" }
      health_data[:table_initialization_requests] = TableInitialization.get_instance.health_check_data_requests
    rescue Exception=>e
      ExceptionHelper.log_exception(e, 'HealthCheckController.health_check_content', additional_msg: "Error reading table_initialization_requests")
      health_data[:warnings] << "\nError reading table_initialization_requests: #{e.class}:#{e.message}"
    end

    begin
      Rails.logger.debug('HealthCheckController.health_check_content') { "Start getting TableInitialization.running_threads_count" }
      current_init_thread_count = TableInitialization.get_instance.running_threads_count(raise_exception_if_locked: true)
      health_data[:current_number_of_table_initialization_threads]  = current_init_thread_count
    rescue Exception=>e
      ExceptionHelper.log_exception(e, 'HealthCheckController.health_check_content', additional_msg: "Error reading current_number_of_table_initialization_threads")
      health_data[:warnings] << "\nError reading current_number_of_table_initialization_threads: #{e.class}:#{e.message}"
    end
    begin
      Rails.logger.debug('HealthCheckController.health_check_content') { "Start getting TableInitialization.health_check_data_threads" }
      health_data[:table_initialization_threads] = TableInitialization.get_instance.health_check_data_threads(jwt_validated: jwt_validated)
    rescue Exception=>e
      ExceptionHelper.log_exception(e, 'HealthCheckController.health_check_content', additional_msg: "Error reading table_initialization_threads")
      health_data[:warnings] << "\nError reading table_initialization_threads: #{e.class}:#{e.message}"
    end

    # get health status of last job executions
    begin
      health_data[:warnings] << ApplicationJob.last_job_warnings
      health_data[:job_info] = ApplicationJob.job_infos
    rescue Exception=>e
      ExceptionHelper.log_exception(e, 'HealthCheckController.health_check_content', additional_msg: "Error reading job states")
      health_data[:warnings] << "\nError reading job states: #{e.class}:#{e.message}"
    end

    # get status of event queue
    begin
      partition_threshold = MovexCdc::Application.config.max_partitions_to_count_as_healthy
      health_data[:event_log_status] = EventLog.health_check_status
      if health_data[:event_log_status][:used_partition_count] && health_data[:event_log_status][:used_partition_count] > partition_threshold
        health_data[:warnings] << "\nPartition count (#{health_data[:event_log_status][:used_partition_count]}) exceeds threshold (#{partition_threshold})"
      end
    rescue Exception=>e
      ExceptionHelper.log_exception(e, 'HealthCheckController.health_check_content', additional_msg: "Error reading event queue states")
      health_data[:warnings] << "\nError reading event queue states: #{e.class}:#{e.message}"
    end

    # get status of final error queue
    begin
      max_count = 2000
      final_error_count = EventLogFinalError.final_error_count(max_count: max_count)
      if final_error_count > 0
        at_least = final_error_count == max_count ? " at least " : ""
        msg = "\nTable #{MovexCdc::Application.config.db_user}.Event_Log_Final_Errors contains#{at_least}#{final_error_count} records!"
        msg << "\nExample error messge: #{EventLogFinalError.an_error_message}" if jwt_validated
        health_data[:warnings] << msg
      end
    rescue Exception=>e
      ExceptionHelper.log_exception(e, 'HealthCheckController.health_check_content', additional_msg: "Error reading final error queue state")
      health_data[:warnings] << "\nError reading final error queue state: #{e.class}:#{e.message}"
    end

    pretty_health_data = JSON.pretty_generate(health_data)

    return pretty_health_data, health_data[:warnings] == '' ? :ok : :conflict
  end

  # Build a record for config_info
  # key should be lower case
  # @param [Array] info_array Array to append the record
  # @param [String] key Key of config parameter
  # @param [String] description Description of config parameter
  # @return [void]
  def build_info_record(info_array, key, description)
    info_record = { name: key.upcase, description: description, value:nil, default_value: nil, startup_config_value: nil }
    info_record[:value] = MovexCdc::Application.config.send(key) if MovexCdc::Application.config.respond_to?(key)
    config_info = MovexCdc::Application.config_attributes(key)
    if config_info
      info_record[:default_value]         = config_info[:default_value]
      info_record[:startup_config_value]  = config_info[:startup_config_value]
    end
    info_array << info_record if !info_record[:value].nil? || !info_record[:default_value].nil? || !info_record[:startup_config_value].nil?
  end

  def garbage_collector_info
    GC.start  # Force a garbage collection cycle
    stats = GC.stat

    gb = (1024 * 1024 * 1024).to_f
    stats.each do |k1, v1|
      if v1.is_a?(Numeric) && v1 > gb/100
        stats[k1] = (v1 / gb).round(3).to_s + ' GB'
      end
      if v1.instance_of?(Hash)
        v1.each do |k2, v2|
          if v2.is_a?(Numeric) && v2 > gb/100
            v1[k2] = (v2 / gb).round(3).to_s + ' GB'
          end
          if v2.instance_of?(Hash)
            v2.each do |k3, v3|
              if v3.is_a?(Numeric) && v3 > gb/100
                v2[k3] = (v3 / gb).round(3).to_s + ' GB'
              end
              if v3.instance_of?(Hash)
                v3.each do |k4, v4|
                  if v4.is_a?(Numeric) && v4 > gb/100
                    v3[k4] = (v4 / gb).round(3).to_s + ' GB'
                  end
                end
              end
            end
          end
        end
      end
    end
    stats
    result = []
    totals = {}
    stats.each do |key, value|
      if value.is_a?(Hash)
        result << { key => value }
      else
        totals[key] = value
      end
    end
    result.unshift({ totals: totals })                                          # add at the first position
    result
  rescue Exception=>e
    ExceptionHelper.log_exception(e, 'HealthCheckController.garbage_collector_info', additional_msg: "Error reading garbage collector info")
    { error: "Error reading garbage collector info: #{e.class}:#{e.message}" }
  end
end
