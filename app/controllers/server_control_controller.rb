require 'json'
class ServerControlController < ApplicationController

  # POST /server_control/set_log_levl
  def set_log_level
    if @current_user.yn_admin != 'Y'
      render json: { errors: ["Access denied! User #{@current_user.email} isn't tagged as admin"] }, status: :unauthorized
    else
      level = params.permit(:log_level)[:log_level]
      raise "Unsupported log level '#{level}'" unless ['DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL'].include? level
      Rails.logger.level = "Logger::#{level}".constantize
    end
  end

  # POST /server_control/set_worker_threads_count
  MAX_WORKER_THREADS=200
  def set_worker_threads_count
    if @current_user.yn_admin != 'Y'
      render json: { errors: ["Access denied! User #{@current_user.email} isn't tagged as admin"] }, status: :unauthorized
    else
      worker_threads_count = params.permit(:worker_threads_count)[:worker_threads_count]
      raise "Number of worker threads (#{worker_threads_count}) not in valid range (0 .. #{MAX_WORKER_THREADS})" if worker_threads_count < 0 || worker_threads_count > MAX_WORKER_THREADS
      ThreadHandling.get_instance.shutdown_processing
      Trixx::Application.config.trixx_initial_worker_threads = worker_threads_count
      ThreadHandling.get_instance.ensure_processing
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
