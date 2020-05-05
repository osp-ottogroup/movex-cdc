require 'json'
class HealthCheckController < ApplicationController
  @@last_call_time = Time.now-100.seconds                                       # ensure enough distance at startup

  # GET /health_check
  def index
    raise "Health check called too frequently" if Time.now - 1.seconds < @@last_call_time   # suppress DOS attacks
    @@last_call_time = Time.now


    @health_data = {
        start_working_timestamp:      ThreadHandling.get_instance.application_startup_timestamp,
        health_check_timestamp:       Time.now,
        warnings:                     '',
        log_level:                    log_level_as_string,
        memory:                       ExceptionHelper.memory_info_hash,
        trixx_kafka_max_bulk_count:   Trixx::Application.config.trixx_kafka_max_bulk_count
    }
    @health_status = :ok

    if Trixx::Application.config.trixx_initial_worker_threads != ThreadHandling.get_instance.thread_count
      @health_data[:warnings] << "\nThread count = #{ThreadHandling.get_instance.thread_count} but should be #{Trixx::Application.config.trixx_initial_worker_threads}"
      @health_status = :conflict
    end

    @health_data[:worker_threads] = ThreadHandling.get_instance.health_check_data

    connection_info = []
    ActiveRecord::Base.connection_pool.connections.each do |conn|
      connection_info << {
          owner_thread: conn.owner&.object_id,
          owner_name:   conn.owner&.name,
          owner_status: conn.owner&.status,
          owner_alive:  conn.owner&.alive?,
          seconds_idle: conn.seconds_idle
      }
    end
    @health_data[:number_of_connections] = connection_info.count
    @health_data[:connection_pool] = connection_info

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
    @health_data[:threads] = thread_info

    render json: JSON.pretty_generate(@health_data), status: @health_status
  end

  # POST /health_check/set_log_levl
  def set_log_level
    if @current_user.yn_admin != 'Y'
      render json: { errors: ["Access denied! User #{@current_user.email} isn't tagged as admin"] }, status: :unauthorized
    else
      level = params.permit(:log_level)[:log_level]
      raise "Unsupported log level '#{level}'" unless ['DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL'].include? level
      Rails.logger.level = "Logger::#{level}".constantize
    end
  end

  private
  def log_level_as_string
    result = case Rails.logger.level
             when 0 then 'DEBUG'
             when 1 then 'INFO'
             when 2 then 'WARN'
             when 3 then 'ERROR'
             when 4 then 'FATAL'
             when 5 then 'UNKNOWN'
             else '[Unsupported]'
             end
    "#{result} (#{Rails.logger.level})"
  end

end
