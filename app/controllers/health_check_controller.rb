require 'json'
class HealthCheckController < ApplicationController

  @@last_call_time = Time.now-100.seconds                                       # ensure enough distance at startup

  # GET /health_check
  def index
    raise "Health check called too frequently" if Time.now - 1.seconds < @@last_call_time   # suppress DOS attacks
    @@last_call_time = Time.now


    @health_data = {
        build_version:                'unknown',
        start_working_timestamp:      ThreadHandling.get_instance.application_startup_timestamp,
        health_check_timestamp:       Time.now,
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



    if Trixx::Application.config.trixx_initial_worker_threads != ThreadHandling.get_instance.thread_count
      @health_data[:warnings] << "\nThread count = #{ThreadHandling.get_instance.thread_count} but should be #{Trixx::Application.config.trixx_initial_worker_threads}"
      @health_status = :conflict
    end

    @health_data[:expected_number_of_worker_threads] = Trixx::Application.config.trixx_initial_worker_threads
    @health_data[:current_number_of_worker_threads]  = ThreadHandling.get_instance.thread_count
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
    @health_data[:connection_pool_stat] = ActiveRecord::Base.connection_pool.stat
    @health_data[:connection_pool] = connection_info.sort_by {|c| "#{c[:owner_name]} #{c[:owner_thread]}" }

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

    render json: JSON.pretty_generate(@health_data), status: @health_status
  end

  # GET /health_check/log_file
  def log_file
    send_file("#{Rails.root.join("log", Rails.env + ".log" )}", :filename => "#{Rails.env}.log")
  end
end
