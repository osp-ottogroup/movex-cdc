require 'json'
require 'java'
class ServerControlController < ApplicationController
  @@restart_worker_threads_mutex = Mutex.new
  @@restart_worker_threads_active=nil

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
      ActivityLog.log_activity(action: "Set server log level to #{level}")
      Rails.logger.level = "Logger::#{level}".constantize
      MovexCdc::Application.config.log_level = level.downcase.to_sym

      # Set log level for log4j, ignore Exception if log4j is not available
      begin
        java_level = eval("Java::OrgApacheLoggingLog4j::Level::#{level}")
        Java::OrgApacheLoggingLog4jCoreConfig::Configurator.setRootLevel(java_level);
      rescue Exception => e
        Rails.logger.warn "ServerControl.set_log_level: log4j not available, ignoring setting log level for log4j. Exception: #{e.class}:#{e.message}"
      end
    end
  end

  # GET /server_control/get_worker_threads_count
  def get_worker_threads_count
    render json: { worker_threads_count:  MovexCdc::Application.config.initial_worker_threads}
  end

  # POST /server_control/set_worker_threads_count
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
      ActivityLog.log_activity(action: "Set number of worker threads from #{MovexCdc::Application.config.initial_worker_threads} to #{worker_threads_count}")

      if worker_threads_count == ThreadHandling.get_instance.thread_count
        Rails.logger.info('ServerControlController.set_worker_threads_count'){ ": Nothing to do because #{worker_threads_count} workers are still active" }
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
  def set_max_transaction_size
    if ApplicationController.current_user.yn_admin != 'Y'
      render json: { errors: ["Access denied! User #{ApplicationController.current_user.email} isn't tagged as admin"] }, status: :unauthorized
    else
      max_transaction_size = params.permit(:max_transaction_size)[:max_transaction_size].to_i
      raise "Max. transaction size (#{max_transaction_size}) should not greater than 0 " if max_transaction_size < 1
      raise_if_restart_active                                                   # protect from multiple executions
      if max_transaction_size == MovexCdc::Application.config.max_transaction_size
        Rails.logger.info "ServerControl.set_max_transaction_size: Nothing to do because max. transaction size = #{max_transaction_size} is still active"
      else
        Rails.logger.warn("ServerControl.set_max_transaction_size") { "Setting max. transaction size from #{MovexCdc::Application.config.max_transaction_size} to #{max_transaction_size}! User = '#{ApplicationController.current_user.email}', client IP = #{client_ip_info}" }
        ActivityLog.log_activity(action: "Set max. transaction size from #{MovexCdc::Application.config.max_transaction_size} to #{max_transaction_size}")
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

  # POST /server_control/reprocess_final_errors
  #
  def reprocess_final_errors
    if ApplicationController.current_user.yn_admin != 'Y'
      render json: { errors: ["Access denied! User #{ApplicationController.current_user.email} isn't tagged as admin"] }, status: :unauthorized
    else
      permitted_params = params.permit(:schema, :table_name)
      schema_name = prepare_param(permitted_params, :schema)
      table_name  = prepare_param(permitted_params, :table_name)
      raise "ServerControlController.reprocess_final_errors: Parameter 'schema' required if 'table_name' specified" if schema_name.nil?  && !table_name.nil?

      join = ''
      where_string = ''
      where_values = {}

      if schema_name
        schema  = Schema.where(name: schema_name).first
        raise "Schema '#{schema_name}' does not exist in MOVEX CDC's config" if schema.nil?
        join = "JOIN Tables t ON t.ID = f.Table_ID"
        where_string = "WHERE t.Schema_ID = :schema_id"
        where_values = { schema_id: schema.id }

        if table_name
          table   = Table.where(schema_id: schema.id, name: table_name).first
          raise "Table '#{table_name}' in schema '#{schema.name}' does not exist in MOVEX CDC's config" if table.nil?
          join = ''                                                             # not needed anymore if table is specified
          where_string = "WHERE f.Table_ID = :table_id"
          where_values = { table_id: table.id }
        end
      end

      reprocess_count = 0
      partitions = [nil]                                                        # default one loop without partitions
      remaining_final_errors = []                                               # Ensure variable is declared outside transaction
      if MovexCdc::Application.partitioning?
        partitions = case MovexCdc::Application.config.db_type
                     when 'ORACLE' then
                       Database.select_all("SELECT Partition_Name FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOG_FINAL_ERRORS' ORDER BY Partition_Position")
                     else
                       raise "Missing rule for #{MovexCdc::Application.config.db_type}"
                     end.map{|p| p.partition_name}
      end
      partitions.each do |partition_name|
        begin
          ActiveRecord::Base.transaction do
            remaining_final_errors = case MovexCdc::Application.config.db_type
                                     when 'ORACLE' then
                                       DatabaseOracle.select_all_limit("SELECT f.*, CAST(f.RowID AS VARCHAR2(30)) Row_ID
                                                                        FROM   Event_Log_Final_Errors#{" PARTITION (#{partition_name})" if partition_name} f
                                                                        #{join}
                                                                        #{where_string}
                                                                        ORDER BY f.ID
                                                                       ", where_values, {fetch_limit: MovexCdc::Application.config.max_transaction_size})
                                     when 'SQLITE' then
                                       ActiveRecord::Base.connection.query_cache.clear  # suppress reading wrong result
                                       Database.select_all("SELECT f.*
                                                            FROM   Event_Log_Final_Errors f
                                                            #{join}
                                                            #{where_string}
                                                            ORDER BY f.ID
                                                            LIMIT #{MovexCdc::Application.config.max_transaction_size}
                                                           ", where_values)
                                     else
                                       raise "Missing rule for #{MovexCdc::Application.config.db_type}"
                                     end
            unless remaining_final_errors.empty?
              insert_final_errors_batch(remaining_final_errors)
              delete_final_errors_batch(remaining_final_errors)
              reprocess_count += remaining_final_errors.count
            end
          end
        end while !remaining_final_errors.empty?
      end

      render json: { reprocess_count:  reprocess_count}
    end
  end

  private
  @@restart_worker_threads_active = nil

  def raise_if_restart_active
    if @@restart_worker_threads_mutex.locked?
      msg = "There's already a request processing and only one simultaneous request for worker threads restart is accepted!\n#{@@restart_worker_threads_active}"
      Rails.logger.warn('ServerControlController.raise_if_restart_active') { msg }
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
        Rails.logger.warn('ServerControlController.restart_worker_threads') { "Restart of worker threads done for: #{context}" }
        ActivityLog.log_activity(action: "Restart of worker threads done for: #{context}")
      rescue Exception => e
        ExceptionHelper.log_exception(e, "ServerControlController.restart_worker_threads")
      ensure
        @@restart_worker_threads_active = nil
      end
    end
  end

  # Delete a batch of records from table
  # called inside a DB transaction
  # @param final_errors Array of records
  def delete_final_errors_batch(final_errors)
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      DatabaseOracle.execute_for_rowid_list(
        stmt: "DELETE /*+ ROWID */ FROM Event_Log_Final_Errors WHERE RowID IN (SELECT /*+ CARDINALITY(d, 1) \"Hint should lead to nested loop and rowid access on Event_Logs \"*/ Column_Value FROM TABLE(?) d)",
        rowid_array: final_errors.map{|f| f['row_id']},
        name: "delete_final_errors_batch with #{final_errors.count} records"
      )
    when 'SQLITE' then
      final_errors.each do |f|
        rows = Database.execute("DELETE FROM Event_Log_Final_Errors WHERE ID=:id", binds: {id: f.id})
        raise "Error in delete_final_errors_batch: Only #{rows} records hit by DELETE instead of exactly one" if rows != 1
      end
    else
      raise "Missing rule for #{MovexCdc::Application.config.db_type}"
    end
  end

  # Insert a batch of records from table Event_Log_Final_Errors into Event_Logs
  # called inside a DB transaction
  # @param final_errors Array of records
  def insert_final_errors_batch(final_errors)
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      DatabaseOracle.execute_for_rowid_list(
        stmt: "INSERT INTO Event_Logs (ID, Table_ID, Operation, DBUser, PayLoad, Msg_Key, Created_At, Transaction_ID)
               SELECT ID, Table_ID, Operation, DBUser, PayLoad, Msg_Key, Created_At, Transaction_ID
               FROM   Event_Log_Final_Errors
               WHERE  RowID IN (SELECT /*+ CARDINALITY(d, 1) \"Hint should lead to nested loop and rowid access on Event_Logs \"*/ Column_Value FROM TABLE(?) d)",
        rowid_array: final_errors.map{|f| f['row_id']},
        name: "insert_final_errors_batch with #{final_errors.count} records"
      )
    when 'SQLITE' then
      final_errors.each do |f|
        Database.execute "INSERT INTO Event_Logs (ID, Table_ID, Operation, DBUser, PayLoad, Msg_Key, Created_At, Transaction_ID)
                          SELECT ID, Table_ID, Operation, DBUser, PayLoad, Msg_Key, Created_At, Transaction_ID
                          FROM   Event_Log_Final_Errors
                          WHERE  ID = :id", binds: { id: f['id'] }
      end
    else
      raise "Missing rule for #{MovexCdc::Application.config.db_type}"
    end
  end

end
