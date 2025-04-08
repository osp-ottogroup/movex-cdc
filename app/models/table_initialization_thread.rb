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
    ExceptionHelper.log_exception(e, 'TableInitializationThread.start_worker_thread', additional_msg: "Request = '#{request[:table_id]}'")
    raise
  end

  # Method process called in own thread
  def process
    @thread = Thread.current
    Rails.logger.info('TableInitializationThread.process'){"New table initialization worker thread created with Table_ID=#{@table_id}, Thread-ID=#{Thread.current.object_id}"}
    Database.set_application_info("table init worker #{@table_id}/process")
    ApplicationController.set_current_user(@current_user)                       # set thread-specific info for the new thread
    ApplicationController.set_current_client_ip_info(@current_client_ip_info)   # set thread-specific info for the new thread
    ActivityLog.log_activity(schema_name: @table.schema.name, table_name: @table.name, action: "Start initial transfer of current table content. Filter = '#{@table.initialization_filter}'")
    @db_session_info = Database.db_session_info                                 # Session ID etc., get information from within separate thread
    Database.set_current_session_network_timeout(timeout_seconds: 86400)        # ensure hanging sessions are cancelled at least after one day
    sleep 1                                                                     # prevent from ORA-01466 if @table.raise_if_table_not_readable_by_movex_cdc is executed too quickly
    @table.raise_if_table_not_readable_by_movex_cdc                             # Check if flashback query is possible on table
    Database.execute @sql
    if MovexCdc::Application.config.db_type != 'ORACLE'                         # For Oracle the activity is logged in the load sql including the result count
      ActivityLog.log_activity(schema_name: @table.schema.name, table_name: @table.name, action: "Successfully finished initial transfer of current table content. Filter = '#{@table.initialization_filter}'")
    end
  rescue Exception => e
    ExceptionHelper.log_exception(e, 'TableInitializationThread.process', additional_msg: "Table_ID = #{@table_id}: Terminating thread due to exception")
    ActivityLog.log_activity(schema_name: @table.schema.name, table_name: @table.name, action: "Error at initial transfer of current table content! #{e.class}:#{e.message}\nExecuted SQL:\n#{@sql}")
  ensure
    begin
      @table.update!(yn_initialization: 'N')                                    # Mark initialization as finished no matter if succesful or not
      TableInitialization.get_instance.remove_from_thread_pool(self)            # unregister from threadpool
      TableInitialization.get_instance.check_for_next_processing                # start next thread if there are still unprocessed requests
    rescue Exception => e
      ExceptionHelper.log_exception(e, 'TableInitializationThread.process', additional_msg: "Table_ID = #{@table_id}: In termination of thread due to exception")
      raise                                                                     # this raise may not be catched because it is the last operation of this thread
    end
  end

  # get Hash with current state info for thread, used e.g. for health check
  def thread_state(options = {})
    retval = {
      table_id:                       @table_id,
      thread_id:                      @thread&.object_id,
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
    @table_id               = request[:table_id]
    @table_name             = request[:table_name]
    @sql                    = request[:sql]
    @db_session_info        = 'set later in new thread'                         # Session ID etc.
    @start_time             = Time.now
    @table                  = Table.find(@table_id)
    @current_user           = request[:current_user]
    @current_client_ip_info = request[:current_client_ip_info]
    @thread                 = nil                                               # set in process
  end

end
