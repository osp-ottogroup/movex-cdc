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
    @max_event_logs_id = 0                                                      # maximum processed id
  end

  MAX_MESSAGE_BULK_COUNT = 10000                                                # Number of records to process within one bulk operation, each operation causes full table scan at Event_Logs
  def process
    # process Event_Logs for  ID mod worker_count = worker_ID for update skip locked
    Rails.logger.info "TransferThread.process: New worker thread created with ID=#{@worker_id}"

    kafka_class = Trixx::Application.config.trixx_kafka_seed_broker == '/dev/null' ? KafkaMock : Kafka
    seed_brokers = Trixx::Application.config.trixx_kafka_seed_broker.split(',').map{|b| b.strip}
    kafka = kafka_class.new(seed_brokers, client_id: "TriXX: #{Socket.gethostname}")
    kafka_producer = kafka.producer(max_buffer_size: MAX_MESSAGE_BULK_COUNT)

    # Loop for ever, check cancel criterial in threadhandling
    idle_sleep_time = 0
    while !@thread_mutex.synchronize { @stop_requested }
      begin
        ActiveRecord::Base.transaction do                                       # commit delete on database only if all messages are processed by kafka
          kafka_producer.transaction do                                         # make messages visible at kafka only if all messages of the batch are processed
            event_logs = read_event_logs_batch                                  # read bulk collection of messages from Event_Logs
            if event_logs.count > 0
              idle_sleep_time = 0                                               # Reset sleep time for next idle time
              event_logs.each do |event_log|
                @max_event_logs_id = event_log.id if event_log.id > @max_event_logs_id  # remember greatest processed ID to ensure lower IDs from pending transactions are also processed neartime
                kafka_producer.produce(prepare_message_from_event_log(event_log), topic: "test-messages")   # Store messages in local collection
              end
              kafka_producer.deliver_messages                                   # bulk transfer of messages from collection to kafka
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
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      if Trixx::Application.partitioning
        # Iterate over older partitions up to MAX_MESSAGE_BULK_COUNT records
        []
      else
        # Ensure that older IDs are processed first
        # only half of MAX_MESSAGE_BULK_COUNT is processed with newer IDs than last execution
        # the other half of MAX_MESSAGE_BULK_COUNT is reserved for older IDs from pending insert transactions that become visible later due to longer transaction duration
        TableLess.select_all("SELECT * FROM Event_Logs WHERE (ID < :max_id AND RowNum <= :max_message_bulk_count) OR RowNum <= :max_message_bulk_count / 2",
                             {max_id: @max_event_logs_id, max_message_bulk_count: MAX_MESSAGE_BULK_COUNT}
        )
      end
    when 'SQLITE' then
      # Ensure that older IDs are processed first
      # only half of MAX_MESSAGE_BULK_COUNT is processed with newer IDs than last execution
      # the other half of MAX_MESSAGE_BULK_COUNT is reserved for older IDs from pending insert transactions that become visible later due to longer transaction duration
      TableLess.select_all("\
SELECT * FROM Event_Logs WHERE ID < :max_id LIMIT #{MAX_MESSAGE_BULK_COUNT}
UNION ALL
SELECT * FROM Event_Logs WHERE LIMIT #{MAX_MESSAGE_BULK_COUNT / 2}",
                           {max_id: @max_event_logs_id}
      )
    else
      raise "Unsupported DB type '#{Trixx::Application.config.trixx_db_type}'"
    end
  end

  def delete_event_logs_batch(event_logs)

  end

  def prepare_message_from_event_log(event_log)

  end
end