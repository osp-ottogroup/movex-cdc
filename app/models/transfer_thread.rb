require 'kafka'
require 'kafka_mock'
require 'socket'

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

    kafka_class = Trixx::Application.config.trixx_kafka_seed_broker == '/dev/null' ? KafkaMock : Kafka
    seed_brokers = Trixx::Application.config.trixx_kafka_seed_broker.split(',').map{|b| b.strip}
    kafka = kafka_class.new(seed_brokers, client_id: "TriXX: #{Socket.gethostname}")
    kafka_producer = kafka.producer

    # Loop for ever, check cancel criterial in threadhandling
    idle_sleep_time = 0
    while !@thread_mutex.synchronize { @stop_requested }
      begin
        ActiveRecord::Base.transaction do                                       # commit delete on database only if all messages are processed by kafka
          kafka_producer.transaction do                                         # make messages visible at kafka only if all messages of the batch are processed
            event_logs = read_event_logs_batch
            if event_logs.count > 0
              idle_sleep_time = 0                                               # Reset sleep time for next idle time
              event_logs.each do |event_log|
                kafka_producer.produce(prepare_message_from_event_log(event_log), topic: "test-messages")
              end
              kafka_producer.deliver_messages
              delete_event_logs_batch(event_logs)
            else
              idle_sleep_time += 1 if idle_sleep_time < 60
              sleep idle_sleep_time                                             # sleep some time if no records are to be processed
            end
          end
        end
      rescue Exception => e
        kafka_producer.clear_buffer                                             # remove all pending (not processed by kafka) messages from producer buffer
        raise e
      end
    end                                                                         # while
  rescue Exception => e
    log_exception(e)
    raise e
  ensure
    kafka_producer&.shutdown                                                    # free kafka connections
    Rails.logger.info "TransferThread(#{@worker_id}).process: stopped"
    ThreadHandling.get_instance.remove_from_pool(self)                          # unregister from threadpool
  end

  def stop_thread                                                               # called from main thread / job
    Rails.logger.info "TransferThread(#{@worker_id}).stop_thread: stop request executed"
    @thread_mutex.synchronize { @stop_requested = true }
  end

  private
  def read_event_logs_batch
    []
  end

  def delete_event_logs_batch(event_logs)

  end

  def prepare_message_from_event_log(event_log)

  end
end