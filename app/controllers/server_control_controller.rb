require 'json'
class ServerControlController < ApplicationController
  @@restart_worker_threads_mutex = Mutex.new

  # GET /server_control/get_log_level
  def get_log_level
    render json: { log_level:  KeyHelper.log_level_as_string}
  end

  # POST /server_control/set_log_level
  def set_log_level
    if ApplicationController.current_user.yn_admin != 'Y'
      render json: { errors: ["Access denied! User #{ApplicationController.current_user.email} isn't tagged as admin"] }, status: :unauthorized
    else
      level = params.permit(:log_level)[:log_level]&.upcase
      raise "Unsupported log level '#{level}'" unless ['DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL'].include? level
      Rails.logger.warn "ServerControl.set_log_level: setting log level to #{level}! User = '#{ApplicationController.current_user.email}', client IP = #{client_ip_info}"
      Rails.logger.level = "Logger::#{level}".constantize
      MovexCdc::Application.config.log_level = level.downcase.to_sym
    end
  end

  # GET /server_control/get_worker_threads_count
  def get_worker_threads_count
    render json: { worker_threads_count:  MovexCdc::Application.config.initial_worker_threads}
  end

  # POST /server_control/set_worker_threads_count
  @@restart_worker_threads_active=nil
  def set_worker_threads_count
    if ApplicationController.current_user.yn_admin != 'Y'
      render json: { errors: ["Access denied! User #{ApplicationController.current_user.email} isn't tagged as admin"] }, status: :unauthorized
    else
      worker_threads_count = params.permit(:worker_threads_count)[:worker_threads_count].to_i

      if ENV['RAILS_MAX_THREADS'] && ENV['RAILS_MAX_THREADS'].to_i < worker_threads_count + MovexCdc::Application.config.threads_for_api_requests + MovexCdc::Application.config.puma_internal_thread_limit
        raise "Environment variable RAILS_MAX_THREADS (#{ENV['RAILS_MAX_THREADS']}) is too low for the requested number of threads! Should be set to greater than the expected number of threads (#{worker_threads_count}) + #{MovexCdc::Application.config.threads_for_api_requests + MovexCdc::Application.config.puma_internal_thread_limit}!"
      end
      raise "Number of worker threads (#{worker_threads_count}) should not be negative" if worker_threads_count < 0

      raise_if_restart_active                                                   # protect from multiple executions
      Rails.logger.warn "ServerControl.set_worker_threads_count: setting number of worker threads from #{MovexCdc::Application.config.initial_worker_threads} to #{worker_threads_count}! User = '#{ApplicationController.current_user.email}', client IP = #{client_ip_info}"
      if worker_threads_count == ThreadHandling.get_instance.thread_count
        Rails.logger.info "ServerControl.set_worker_threads_count: Nothing to do because #{worker_threads_count} workers are still active"
      else
        MovexCdc::Application.config.initial_worker_threads = worker_threads_count
        restart_worker_threads "Worker count: current=#{ThreadHandling.get_instance.thread_count}, new=#{worker_threads_count}"
      end
    end
  end

  # GET /server_control/get_max_transaction_size
  def get_max_transaction_size
    render json: { max_transaction_size:  MovexCdc::Application.config.max_transaction_size}
  end

  # POST /server_control/set_max_transaction_size
  @@restart_worker_threads_active=nil
  def set_max_transaction_size
    if ApplicationController.current_user.yn_admin != 'Y'
      render json: { errors: ["Access denied! User #{ApplicationController.current_user.email} isn't tagged as admin"] }, status: :unauthorized
    else
      max_transaction_size = params.permit(:max_transaction_size)[:max_transaction_size].to_i
      raise "Max. transaction size (#{max_transaction_size}) should not greater than 0 " if max_transaction_size < 1
      raise_if_restart_active                                                   # protect from multiple executions
      Rails.logger.warn "ServerControl.set_max_transaction_size: setting max. transaction size from #{MovexCdc::Application.config.max_transaction_size} to #{max_transaction_size}! User = '#{ApplicationController.current_user.email}', client IP = #{client_ip_info}"
      if max_transaction_size == MovexCdc::Application.config.max_transaction_size
        Rails.logger.info "ServerControl.set_max_transaction_size: Nothing to do because max. transaction size = #{max_transaction_size} is still active"
      else
        context = "max. transaction size: current=#{MovexCdc::Application.config.max_transaction_size}, new=#{max_transaction_size}"
        MovexCdc::Application.config.max_transaction_size = max_transaction_size
        restart_worker_threads context
      end
    end
  end

  # POST /server_control/terminate
  def terminate
    if ApplicationController.current_user.yn_admin != 'Y'
      render json: { errors: ["Access denied! User #{ApplicationController.current_user.email} isn't tagged as admin"] }, status: :unauthorized
    else
      Rails.logger.warn "ServerControl.terminate: shutdown requested by API function! User = '#{ApplicationController.current_user.email}', client IP = #{client_ip_info}"
      Process.kill(:TERM, Process.pid)                                          # send TERM signal to myself
    end
  end

  private
  @@restart_worker_threads_active = nil

  def raise_if_restart_active
    if @@restart_worker_threads_mutex.locked?
      msg = "There's already a request processing and only one simultaneous request for worker threads restart is accepted!\n#{@@restart_worker_threads_active}"
      Rails.logger.warn msg
      raise msg
    end
  end

  def restart_worker_threads(context)
    @@restart_worker_threads_mutex.synchronize do
      begin
        @@restart_worker_threads_active = "Waiting for shutdown_processing. #{context}"
        ThreadHandling.get_instance.shutdown_processing
        @@restart_worker_threads_active = "Waiting for ensure_processing. #{context}"
        ThreadHandling.get_instance.ensure_processing
      rescue Exception => e
        ExceptionHelper.log_exception(e, "ServerControlController.restart_worker_threads")
      ensure
        @@restart_worker_threads_active = nil
      end
    end
  end
end
