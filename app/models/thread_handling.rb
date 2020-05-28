class ThreadHandling
  attr_reader :application_startup_timestamp

  @@instance = nil
  def self.get_instance
    @@instance = ThreadHandling.new if @@instance.nil?
    @@instance
  end

  # Ensure that matching number of worker threads is active
  def ensure_processing
    current_thread_pool_size = @thread_pool_mutex.synchronize { @thread_pool.count }

    # calculate required number of worker threads
    required_number_of_threads = Trixx::Application.config.trixx_initial_worker_threads
    Rails.logger.info "ThreadHandling.ensure_processing: Current number of threads = #{current_thread_pool_size}, required number of threads = #{required_number_of_threads}, shudown requested = #{@shutdown_requested}"
    unless @shutdown_requested                                                  # don't start new worker during server shutdown

      @thread_pool_mutex.synchronize do
        Rails.logger.debug "ThreadHandling.ensure_processing: within @thread_pool_mutex.synchronize"
        current_thread_pool_size.downto(required_number_of_threads+1) do |i|    # reduce the number of threads if necessary
          Rails.logger.debug "ThreadHandling.ensure_processing: stopping thread if there are too much threads"
          @thread_pool[i-1].stop_thread                                         # inform TransferThread.process it should terminate
        end

        current_thread_pool_size.upto(required_number_of_threads-1) do          # increase the number of threads if necessary
          Rails.logger.debug "ThreadHandling.ensure_processing: starting worker thread because there are not enough"
          memory_buffer_per_worker = Trixx::Application.config.trixx_kafka_total_buffer_size_mb * 1024 * 1024 / required_number_of_threads
          @thread_pool << TransferThread.create_worker(next_free_worker_id, {
              max_transaction_size:     Trixx::Application.config.trixx_max_transaction_size,
              max_message_bulk_count:   Trixx::Application.config.trixx_kafka_max_bulk_count,
              max_buffer_bytesize:      memory_buffer_per_worker
          }
          )  # add worker to pool
          sleep 2                                                               # don't start all workers at once
        end
      end
    end
    StatisticCounterConcentrator.get_instance.flush_to_db                       # write statistics to DB

  end

  SHUTDOWN_TIMEOUT_SECS = 100
  # graceful shutdown processing of transfer threads at rails exit
  def shutdown_processing
    @thread_pool_mutex.synchronize do
      @shutdown_requested = true                                                # prevent ensure_processing from recreating shut down threads
      @thread_pool.each do |worker|
        worker.stop_thread                                                      # inform TransferThread.process should terminate
      end
    end

    shutdown_wait_time = 0
    while @thread_pool_mutex.synchronize { @thread_pool.count } > 0
      sleep 0.1                                                                 # Wait for TransferThread.process to terminate
      shutdown_wait_time += 0.1
      break if shutdown_wait_time > SHUTDOWN_TIMEOUT_SECS
    end
    if @thread_pool_mutex.synchronize { @thread_pool.count } == 0
      Rails.logger.info "All TransferThread worker are stopped now, shutting down"
      @shutdown_requested = false                                               # Reset state so next ensure_processing may start again
    else
      Rails.logger.info "ThreadHandling.shutdown_processing: Not all TransferThread worker are stopped now after #{SHUTDOWN_TIMEOUT_SECS} seconds (#{@thread_pool_mutex.synchronize { @thread_pool.count } } remaining) , shutting down nethertheless"
    end
    StatisticCounterConcentrator.get_instance.flush_to_db                       # write statistics to DB after stop of worker threads
  end

  # remove worker from pool: called from other threads after finishing TransferThread.process
  def remove_from_pool(worker)
    @thread_pool_mutex.synchronize do
      @thread_pool.delete(worker)
    end
  end

  def thread_count
    @thread_pool_mutex.synchronize { @thread_pool.count }
  end

  # get health check status from all worker threads
  def health_check_data
    result = []
    @thread_pool_mutex.synchronize do
      @thread_pool.each do |t|
        result << t.thread_state
      end
    end
    result
  end

  private
  def initialize                                                                # get singleton by get_instance only
    @thread_pool = []
    @thread_pool_mutex = Mutex.new                                              # Ensure synchronized operations on @thread_pool
    @shutdown_requested = false                                                 # Semaphore to prevent ensure_processing from recreating shut down threads
    @application_startup_timestamp = Time.now
  end

  # get worker_id for new worker from end of list or gap, called from inside Mutex.synchronize
  def next_free_worker_id
    worker_id = 0                                                               # Default for emty list
    used_ids = @thread_pool.map{|t| t.worker_id}.sort
    while used_ids.include? worker_id
      worker_id += 1
    end
    worker_id
  end

end