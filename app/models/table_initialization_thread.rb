require 'database'
require 'table'
require 'exception_helper'

class TableInitializationThread
  attr_reader :table_id, :table_name, :sql

  def self.start_worker_thread(request)
    worker = TableInitializationThread.new(request)
    thread = Thread.new do
      worker.process
    end
    thread.name = "TableInitializationThread :#{request[:table_id]}"
    thread.report_on_exception = false                                          # don't report the last exception in thread because it is already logged by thread itself
    worker
  rescue Exception => e
    ExceptionHelper.log_exception(e, "TableInitializationThread.start_worker_thread (#{request[:table_id]})")
    raise
  end

  # Method process called in own thread
  def process
    Rails.logger.info('TableInitializationThread.process'){"New table initialization worker thread created with Table_ID=#{@table_id}, Thread-ID=#{Thread.current.object_id}"}
    Database.set_application_info("table init worker #{@table_id}/process")
    ActivityLog.new(user_id: @user_id, schema_name: @table.schema.name, table_name: @table.name, client_ip: @client_ip, action: "Start initial transfer of current table content. Filter = '#{@table.initialization_filter}'" ).save!
    @db_session_info = Database.db_session_info                                 # Session ID etc., get information from within separate thread
    Database.set_current_session_network_timeout(timeout_seconds: 86400)        # ensure hanging sessions are cancelled at least after one day
    sleep 1                                                                     # prevent from ORA-01466 if @table.raise_if_table_not_readable_by_trixx is executed too quickly
    @table.raise_if_table_not_readable_by_trixx                                 # Check if flashback query is possible on table
    Database.execute @sql
    ActivityLog.new(user_id: @user_id, schema_name: @table.schema.name, table_name: @table.name, client_ip: @client_ip, action: "Successfully finished initial transfer of current table content. Filter = '#{@table.initialization_filter}'" ).save!
  rescue Exception => e
    ExceptionHelper.log_exception(e, "TableInitializationThread.process #{@table_id}: Terminating thread due to exception")
    ActivityLog.new(user_id: @user_id, schema_name: @table.schema.name, table_name: @table.name, client_ip: @client_ip, action: "Error at initial transfer of current table content! #{e.class}:#{e.message}" ).save!
  ensure
    @table.update!(yn_initialization: 'N')                                      # Mark initialization as finished no matter if succesful or not
    TableInitialization.get_instance.remove_from_thread_pool(self)              # unregister from threadpool
    TableInitialization.get_instance.check_for_next_processing                  # start next thread if there are still unprocessed requests
  end

  # get Hash with current state info for thread, used e.g. for health check
  def thread_state(options = {})
    retval = {
      table_id:                       @table_id,
      thread_id:                      Thread.current.object_id,
      table_name:                     @table_name,
      db_session_info:                @db_session_info,
      start_time:                     @start_time,
      sql:                            @sql
    }
    retval[:stacktrace] = @thread&.backtrace unless options[:without_stacktrace]
    retval
  end

  private

  def initialize(request)
    @table_id         = request[:table_id]
    @table_name       = request[:table_name]
    @sql              = request[:sql]
    @db_session_info  = 'set later in new thread'                 # Session ID etc.
    @start_time       = Time.now
    @table            = Table.find(@table_id)
    @user_id          = request[:user_options]&.fetch(:user_id)
    @client_ip        = request[:user_options]&.fetch(:client_ip_info)
  end

end
