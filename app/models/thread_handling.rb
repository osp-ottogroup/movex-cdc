class ThreadHandling

  @@instance = nil
  def self.get_instance
    @@instance = ThreadHandling.new if @@instance.nil?
    @@instance
  end

  INITIAL_NUMBER_OF_THREADS = 10                                                # how many worker threads should be created at startup
  # Ensure that matching number of worker threads is active
  def ensure_processing
    # calculate required number of worker threads
    required_number_of_threads = @thread_pool.count                             # Current state as default
    required_number_of_threads = INITIAL_NUMBER_OF_THREADS if @thread_pool.count == 0 # Startup setup

    @thread_pool_mutex.synchronize do
      unless @shutdown_requested
        while required_number_of_threads < @thread_pool.count                   # reduce the number of threads
          @thread_pool.last.stop_thread                                         # wait until TransferThread.process has terminated
          @thread_pool.delete_at(@thread_pool.count-1)                          # remove from pool
        end

        while required_number_of_threads > @thread_pool.count                   # increase the number of threads
          @thread_pool << TransferThread.create_worker(@thread_pool.count)      # add worker to pool
        end
      end
    end

  end

  # graceful shutdown processing of transfer threads at rails exit
  def shutdown_processing
    @thread_pool_mutex.synchronize do
      @shutdown_requested = true                                                # prevent ensure_processing from recreating shut down threads
      while @thread_pool.count > 0
        @thread_pool.last.stop_thread                                           # wait until TransferThread.process has terminated
        @thread_pool.delete_at(@thread_pool.count-1)                            # remove from pool
      end
    end
  end

  def thread_count
    @thread_pool.count
  end

  private
  def initialize                                                                # get singleton by get_instance only
    @thread_pool = []
    @thread_pool_mutex = Mutex.new                                              # Ensure synchronized operations on @@thread_pool
    @shutdown_requested = false                                                 # Semaphore to prevent ensure_processing from recreating shut down threads
  end

end