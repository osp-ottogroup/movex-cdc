class TransferThread
  include ExceptionHelper
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
    @thread_mutex = Mutex.new                                                   # Ensure access on instance variables from two threads
  end

  def process
    # process Event_Logs for  ID mod worker_count = worker_ID for update skip locked
    Rails.logger.info "TransferThread.process: New worker thread created with ID=#{@worker_id}"

    # Loop for ever, check cancel criterial in threadhandling
    while !@thread_mutex.synchronize { @stop_requested }
      sleep 1

    end
    Rails.logger.info "TransferThread(#{@worker_id}).process: stopped"
  rescue Exception => e
    log_exception(e)
  ensure
    ThreadHandling.get_instance.remove_from_pool(self)                          # unregister from threadpool
  end

  def stop_thread                                                               # called from main thread / job
    Rails.logger.info "TransferThread(#{@worker_id}).stop_thread: stop request executed"
    @thread_mutex.synchronize { @stop_requested = true }
  end

end