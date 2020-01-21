class TransferThread
  attr_reader :worker_id

  def self.create_worker(worker_id)
    thread = Thread.new{ TransferThread.new(worker_id).process }
    thread.name = "TransferThread :#{worker_id}"
  rescue Exception => e
    Rails.logger.error "Exception #{e.message} raised in WorkerThread.create_worker (#{worker_id})"
  end

  def initialize(worker_id)
    @worker_id = worker_id
  end

  def process

  end

end