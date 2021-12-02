# functions for initial transfer of current table data at first trigger creation
# including queuing of initialization requests from trigger generation
class TableInitialization

  @@instance = nil
  def self.get_instance
    @@instance = TableInitialization.new if @@instance.nil?
    @@instance
  end

  def add_table_initialization(table_id, table_name, sql, user_options)
    @init_requests_mutex.synchronize { @init_requests << {table_id: table_id, table_name: table_name, sql: sql, user_options: user_options} }
    check_for_next_processing
  end

  # Check if tread pool size allows processing of next request, triggered at new reauests and if running requests finish
  def check_for_next_processing
    if init_requests_count > 0 && running_threads_count < Trixx::Application.config.max_simultaneous_table_initializations
      begin
        request = @init_requests_mutex.synchronize { @init_requests.delete_at(0) }  # remove next request from queue
        @thread_pool_mutex.synchronize { @thread_pool << TableInitializationThread.start_worker_thread(request) }
      rescue Exception => e
        ExceptionHelper.log_exception(e, "TableInitialization.check_for_next_processing")
        raise
      end
    end
  end

  def running_threads_count(raise_exception_if_locked: false)
    ExceptionHelper.limited_wait_for_mutex(mutex: @thread_pool_mutex, raise_exception: raise_exception_if_locked)
    @thread_pool_mutex.synchronize { @thread_pool.count }
  end

  def init_requests_count(raise_exception_if_locked: false)
    ExceptionHelper.limited_wait_for_mutex(mutex: @init_requests_mutex, raise_exception: raise_exception_if_locked)
    @init_requests_mutex.synchronize { @init_requests.count }
  end

  # remove worker from pool: called from other threads after finishing TableInitializationThread.process
  def remove_from_thread_pool(worker)
    ExceptionHelper.warn_with_backtrace "TableInitialization.remove_from_thread_pool: Mutex @thread_pool_mutex is locked by another thread! Waiting until Mutex is freed." if @thread_pool_mutex.locked?
    @thread_pool_mutex.synchronize do
      @thread_pool.delete(worker)
    end
  end

  # get health check status from all initialization requests
  def health_check_data_requests
    result = []
    ExceptionHelper.limited_wait_for_mutex(mutex: @init_requests_mutex, raise_exception: true)
    @init_requests_mutex.synchronize do
      @init_requests.each do |i|
        result << i
      end
    end
  end

  # get health check status from all initialization threads
  def health_check_data_threads
    result = []
    ExceptionHelper.limited_wait_for_mutex(mutex: @thread_pool_mutex, raise_exception: true)
    @thread_pool_mutex.synchronize do
      @thread_pool.each do |t|
        result << t.thread_state
      end
    end
    result.sort_by {|e| e[:table_id]}
  end

  private
  def initialize                                                                # get singleton by get_instance only
    @init_requests          = []                                                # List of requested initializations SQLs from trigger generation
    @init_requests_mutex    = Mutex.new                                         # Ensure synchronized operations on @init_requests
    @thread_pool            = []                                                # List of currently running initializations
    @thread_pool_mutex      = Mutex.new                                         # Ensure synchronized operations on @thread_pool
  end


end