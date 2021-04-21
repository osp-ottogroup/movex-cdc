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

  def process
    Rails.logger.info('TableInitializationThread.process'){"New table initialization worker thread created with Table_ID=#{@table_id}, Thread-ID=#{Thread.current.object_id}"}
    Database.set_application_info("table init worker #{@table_id}/process")
    @db_session_info = Database.db_session_info                                 # Session ID etc., get information from within separate thread
    Database.set_current_session_network_timeout(timeout_seconds: 86400)        # ensure hanging sessions are cancelled at least after one day
    @table.raise_if_table_not_readable_by_trixx                                 # Check if flashback query is possible on table
    Database.execute @sql
    # TODO: add activity_logs record
  rescue Exception => e
    log_exception(e, "TableInitializationThread.process #{@table_id}: Terminating thread due to exception")
    # TODO: add activity_logs record
    raise
  ensure
    TableInitialization.get_instance.remove_from_thread_pool(self)              # unregister from threadpool
    TableInitialization.get_instance.check_for_next_processing                  # start next thread if there are still unprocessed requests
    @table.update!(yn_initialization: 'N')                                      # Mark initialization as finished no matter if succesful or not
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

  end

end
