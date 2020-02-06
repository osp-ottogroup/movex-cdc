class TransferThread
  attr_reader :worker_id

  def self.create_worker(worker_id)
    worker = TransferThread.new(worker_id)
    thread = Thread.new{ worker.process }
    thread.name = "TransferThread :#{worker_id}"
    worker
  rescue Exception => e
    Rails.logger.error "Exception #{e.message} raised in WorkerThread.create_worker (#{worker_id})"
  end

  def initialize(worker_id)
    @worker_id = worker_id
    @stop_requested = false
    @stop_completed = false
    @thread_mutex = Mutex.new                                                   # Ensure access on instance variables from two threads
  end

  def process
    # process Event_Logs for  ID mod worker_count = worker_ID for update skip locked
    Rails.logger.info "TransferThread.process: New worker thread created with ID=#{@worker_id}"

    # Loop for ever, check cancel criterial in threadhandling
    while !@stop_completed
      sleep 1

      @thread_mutex.synchronize do
        if @stop_requested
          Rails.logger.info "TransferThread(#{@worker_id}).process: stop request accepted"
          @stop_completed = true
        end
      end
    end
    Rails.logger.info "TransferThread(#{@worker_id}).process: stopped"
  end

  def stop_thread                                                               # called from mail thread / job
    Rails.logger.info "TransferThread(#{@worker_id}).stop_thread: stop request executed"
    @thread_mutex.synchronize { @stop_requested = true }
    local_stop_completed = false
    while !local_stop_completed
      sleep(0.1)                                                                # wait for process termination
      @thread_mutex.synchronize { local_stop_completed = @stop_completed }      # check if process has terminated
    end
    Rails.logger.info "TransferThread(#{@worker_id}).stop_thread: stop request completed"
  end

end