require 'json'
class HealthCheckController < ApplicationController
  @@last_call_time = Time.now-100.seconds                                       # ensure enough distance at startup

  # GET /health_check
  def index
    raise "Health check called too frequently" if Time.now - 1.seconds < @@last_call_time   # suppress DOS attacks
    @@last_call_time = Time.now


    @health_data = {
        start_working_timestamp: ThreadHandling.get_instance.application_startup_timestamp,
        health_check_timestamp: Time.now,
        warnings: '',
        memory: ExceptionHelper.memory_info_hash
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

end
