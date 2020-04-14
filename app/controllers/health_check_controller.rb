require 'json'
class HealthCheckController < ApplicationController
  @@last_call_time = Time.now-100.seconds                                       # ensure enough distance at startup

  # GET /health_check
  def index
    raise "Health check called too frequently" if Time.now - 1.seconds < @@last_call_time   # suppress DOS attacks
    @@last_call_time = Time.now


    @health_data = {
        timestamp: Time.now,
        warnings: '',
        memory: ExceptionHelper.memory_info_hash
    }
    @health_status = :ok

    if Trixx::Application.config.trixx_initial_worker_threads != ThreadHandling.get_instance.thread_count
      @health_data[:warnings] << "\nThread count = #{ThreadHandling.get_instance.thread_count} but should be #{Trixx::Application.config.trixx_initial_worker_threads}"
      @health_status = :conflict
    end

    @health_data[:worker_threads] = ThreadHandling.get_instance.health_check_data

    render json: JSON.pretty_generate(@health_data), status: @health_status
  end

end
