require 'json'
class ServerControlController < ApplicationController

  # GET /server_control/get_log_level
  def get_log_level
    render json: { log_level:  KeyHelper.log_level_as_string}
  end

  # POST /server_control/set_log_level
  def set_log_level
    if @current_user.yn_admin != 'Y'
      render json: { errors: ["Access denied! User #{@current_user.email} isn't tagged as admin"] }, status: :unauthorized
    else
      level = params.permit(:log_level)[:log_level]&.upcase
      raise "Unsupported log level '#{level}'" unless ['DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL'].include? level
      Rails.logger.warn "ServerControl.set_log_level: setting log level to #{level}! User = '#{@current_user.email}', client IP = #{client_ip_info}"
      Rails.logger.level = "Logger::#{level}".constantize
    end
  end

  # GET /server_control/get_worker_threads_count
  def get_worker_threads_count
    render json: { worker_threads_count:  Trixx::Application.config.trixx_initial_worker_threads}
  end

  # POST /server_control/set_worker_threads_count
  @@set_worker_threads_count_active=nil
  def set_worker_threads_count
    if @current_user.yn_admin != 'Y'
      render json: { errors: ["Access denied! User #{@current_user.email} isn't tagged as admin"] }, status: :unauthorized
    else
      worker_threads_count = params.permit(:worker_threads_count)[:worker_threads_count].to_i

      if ENV['RAILS_MAX_THREADS'] && ENV['RAILS_MAX_THREADS'].to_i < worker_threads_count + Trixx::Application.config.trixx_threads_for_api_requests + Trixx::Application.config.puma_internal_thread_limit
        raise "Environment variable RAILS_MAX_THREADS (#{ENV['RAILS_MAX_THREADS']}) is too low for the requested number of threads! Should be set to greater than the expected number of threads (#{worker_threads_count}) + #{Trixx::Application.config.trixx_threads_for_api_requests + Trixx::Application.config.puma_internal_thread_limit}!"
      end
      raise "Number of worker threads (#{worker_threads_count}) should not be negative" if worker_threads_count < 0

      raise "server_control/set_worker_threads_count: There's already a request processing and only one simultaneous request is accepted! #{@@set_worker_threads_count_active}" if !@@set_worker_threads_count_active.nil?
      Rails.logger.warn "ServerControl.set_worker_threads_count: setting number of worker threads to #{worker_threads_count}! User = '#{@current_user.email}', client IP = #{client_ip_info}"
      if worker_threads_count == ThreadHandling.get_instance.thread_count
        Rails.logger.info "ServerControl.set_worker_threads_count: Nothing to do because #{worker_threads_count} workers are still active"
      else
        begin
          @@set_worker_threads_count_active = "Waiting for shutdown_processing. Worker count: current=#{ThreadHandling.get_instance.thread_count}, new=#{worker_threads_count}"
          ThreadHandling.get_instance.shutdown_processing
          Trixx::Application.config.trixx_initial_worker_threads = worker_threads_count
          @@set_worker_threads_count_active = "Waiting for ensure_processing. Worker count: current=#{ThreadHandling.get_instance.thread_count}, new=#{worker_threads_count}"
          ThreadHandling.get_instance.ensure_processing
        ensure
          @@set_worker_threads_count_active=nil
        end
      end
    end
  end

  # POST /server_control/terminate
  def terminate
    if @current_user.yn_admin != 'Y'
      render json: { errors: ["Access denied! User #{@current_user.email} isn't tagged as admin"] }, status: :unauthorized
    else
      Rails.logger.warn "ServerControl.terminate: shutdown requested by API function! User = '#{@current_user.email}', client IP = #{client_ip_info}"
      Process.kill(:TERM, Process.pid)                                          # send TERM signal to myself
    end
  end

end
