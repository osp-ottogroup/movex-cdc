require 'json'
class ServerControlController < ApplicationController

  # POST /server_control/set_log_levl
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

  # POST /server_control/set_worker_threads_count
  def set_worker_threads_count
    if @current_user.yn_admin != 'Y'
      render json: { errors: ["Access denied! User #{@current_user.email} isn't tagged as admin"] }, status: :unauthorized
    else
      worker_threads_count = params.permit(:worker_threads_count)[:worker_threads_count].to_i

      if ENV['RAILS_MAX_THREADS'] && ENV['RAILS_MAX_THREADS'].to_i < worker_threads_count * 2
        raise "Environment variable RAILS_MAX_THREADS (#{ENV['RAILS_MAX_THREADS']}) is too low for the requested number of threads! Should be set to greater than the expected number of threads (#{worker_threads_count}) * 2 !"
      end
      raise "Number of worker threads (#{worker_threads_count}) not in valid range (0 .. #{ENV['RAILS_MAX_THREADS'].to_i / 2})" if worker_threads_count < 0

      Rails.logger.warn "ServerControl.set_worker_threads_count: setting number of worker threads to #{worker_threads_count}! User = '#{@current_user.email}', client IP = #{client_ip_info}"
      if worker_threads_count == ThreadHandling.get_instance.thread_count
        Rails.logger.info "ServerControl.set_worker_threads_count: Nothing to do because #{worker_threads_count} workers are still active"
      else
        ThreadHandling.get_instance.shutdown_processing
        Trixx::Application.config.trixx_initial_worker_threads = worker_threads_count
        ThreadHandling.get_instance.ensure_processing
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
