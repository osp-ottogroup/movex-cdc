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


  end

  private
  def initialize                                                                # get singleton by get_instance only
    @thread_pool = []
    @thread_pool_mutex = Mutex.new                                              # Ensure synchronized operations on @@thread_pool
  end

end