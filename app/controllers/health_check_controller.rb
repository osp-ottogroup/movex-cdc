require 'json'
class HealthCheckController < ApplicationController

  @@last_call_time = Time.now-100.seconds                                       # ensure enough distance at startup

  # GET /health_check
  def index
    raise "Health check called too frequently" if Time.now - 1.seconds < @@last_call_time   # suppress DOS attacks
    @@last_call_time = Time.now


    @health_data = {
        health_check_timestamp:       Time.now,
        build_version:                'unknown',
        database_url:                 Trixx::Application.config.trixx_db_url,
        kafka_seed_broker:            Trixx::Application.config.trixx_kafka_seed_broker,
        start_working_timestamp:      ThreadHandling.get_instance.application_startup_timestamp,
        warnings:                     '',
        log_level:                    "#{KeyHelper.log_level_as_string} (#{Rails.logger.level})",
        memory:                       ExceptionHelper.memory_info_hash,
        trixx_kafka_max_bulk_count:   Trixx::Application.config.trixx_kafka_max_bulk_count
    }
    @health_status = :ok

    begin
      @health_data[:build_version] = File.read(Rails.root.join('build_version'))
    rescue Errno::ENOENT
      @health_data[:build_version] = 'File ./build_version does not exist'
    end

    begin
      Rails.logger.debug "HealthCheckController.index: Start getting current thread count"
      current_thread_count = ThreadHandling.get_instance.thread_count(raise_exception_if_locked: true)
      @health_data[:current_number_of_worker_threads]  = current_thread_count
      if Trixx::Application.config.trixx_initial_worker_threads != current_thread_count
        @health_data[:warnings] << "\nThread count = #{current_thread_count} but should be #{Trixx::Application.config.trixx_initial_worker_threads}"
        @health_status = :conflict
      end
    rescue Exception=>e
      @health_data[:warnings] << "\nError reading current_number_of_worker_threads: #{e.class}:#{e.message}"
      @health_status = :conflict
    end

    @health_data[:expected_number_of_worker_threads] = Trixx::Application.config.trixx_initial_worker_threads

    begin
      Rails.logger.debug "HealthCheckController.index: Start getting ThreadHandling.health_check_data"
      @health_data[:worker_threads] = ThreadHandling.get_instance.health_check_data
    rescue Exception=>e
      @health_data[:warnings] << "\nError reading worker_threads: #{e.class}:#{e.message}"
      @health_status = :conflict
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
    @health_data[:connection_pool_stat] = ActiveRecord::Base.connection_pool.stat
    @health_data[:connection_pool] = connection_info.sort_by {|c| "#{c[:owner_name]} #{c[:owner_thread]}" }

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
    @health_data[:number_of_threads] = thread_info.count
    @health_data[:threads] = thread_info.sort_by {|t| t[:object_id] }


    begin
      Rails.logger.debug "HealthCheckController.index: Start getting TableInitialization.init_requests_count"
      current_init_requests_count = TableInitialization.get_instance.init_requests_count(raise_exception_if_locked: true)
      @health_data[:current_number_of_table_initialization_requests]  = current_init_requests_count
    rescue Exception=>e
      @health_data[:warnings] << "\nError reading current_number_of_table_initialization_requests: #{e.class}:#{e.message}"
      @health_status = :conflict
    end
    begin
      Rails.logger.debug "HealthCheckController.index: Start getting TableInitialization.health_check_data_requests"
      @health_data[:table_initialization_requests] = TableInitialization.get_instance.health_check_data_requests
    rescue Exception=>e
      @health_data[:warnings] << "\nError reading table_initialization_requests: #{e.class}:#{e.message}"
      @health_status = :conflict
    end

    begin
      Rails.logger.debug "HealthCheckController.index: Start getting TableInitialization.running_threads_count"
      current_init_thread_count = TableInitialization.get_instance.running_threads_count(raise_exception_if_locked: true)
      @health_data[:current_number_of_table_initialization_threads]  = current_init_thread_count
    rescue Exception=>e
      @health_data[:warnings] << "\nError reading current_number_of_table_initialization_threads: #{e.class}:#{e.message}"
      @health_status = :conflict
    end
    begin
      Rails.logger.debug "HealthCheckController.index: Start getting TableInitialization.health_check_data_threads"
      @health_data[:table_initialization_threads] = TableInitialization.get_instance.health_check_data_threads
    rescue Exception=>e
      @health_data[:warnings] << "\nError reading table_initialization_threads: #{e.class}:#{e.message}"
      @health_status = :conflict
    end




    render json: JSON.pretty_generate(@health_data), status: @health_status
  end

  # GET /health_check/log_file
  def log_file
    send_file("#{Rails.root.join("log", Rails.env + ".log" )}", :filename => "#{Rails.env}.log")
  end
end
