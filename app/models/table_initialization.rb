# functions for initial transfer of current table data at first trigger creation
# including queuing of initialization requests from trigger generation
class TableInitialization

  @@instance = nil
  def self.get_instance
    @@instance = TableInitialization.new if @@instance.nil?
    @@instance
  end

  def add_table_initialization(sql)
    @@init_requests_mutex.synchronize { @init_requests << sql }
    check_for_next_processing
  end

  # Check if tread pool size allows processing of next request, triggered at new reauests and if running requests finish
  def check_for_next_processing
    if init_requests_count > 0 && running_threads_count < Trixx::Application.config.trixx_max_simultaneous_table_initializations
      # Start next thread for processing
    end
  end

  def running_threads_count
    @thread_pool_mutex.synchronize { @thread_pool.count }
  end

  def init_requests_count
    @init_requests_mutex.synchronize { @init_requests.count }
  end

  private
  def initialize                                                                # get singleton by get_instance only
    @init_requests          = []                                                # List of requested initializations from trigger generation
    @init_requests_mutex    = Mutex.new                                         # Ensure synchronized operations on @init_requests
    @thread_pool            = []                                                # List of currently running initializations
    @thread_pool_mutex      = Mutex.new                                         # Ensure synchronized operations on @thread_pool
  end


end