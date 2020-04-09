require 'kafka'
require 'kafka_mock'
require 'socket'
require 'table_less'
require 'schema'
require 'exception_helper'

class TransferThread
  attr_reader :worker_id

  def self.create_worker(worker_id)
    worker = TransferThread.new(worker_id)
    thread = Thread.new{ worker.process }
    thread.name = "TransferThread :#{worker_id}"
    worker
  rescue Exception => e
    ExceptionHelper.log_exception(e, "WorkerThread.create_worker (#{worker_id})")
  end

  def initialize(worker_id)
    @worker_id = worker_id
    @stop_requested = false
    @thread_mutex = Mutex.new                                                   # Ensure access on instance variables from two threads
    @max_event_logs_id = 0                                                      # maximum processed id
    @schemas_cache = {}                                                         # cache for match id to name
    @tables_cache = {}                                                          # cache for match id to name
  end

  MAX_MESSAGE_BULK_COUNT = 10000                                                # Number of records to process within one bulk operation, each operation causes full table scan at Event_Logs
  MAX_EXCEPTION_RETRY=10                                                        # max. number of retries after exception
  def process
    # process Event_Logs for  ID mod worker_count = worker_ID for update skip locked
    Rails.logger.info "TransferThread.process: New worker thread created with ID=#{@worker_id}"

    kafka_class = Trixx::Application.config.trixx_kafka_seed_broker == '/dev/null' ? KafkaMock : Kafka
    seed_brokers = Trixx::Application.config.trixx_kafka_seed_broker.split(',').map{|b| b.strip}
    kafka = kafka_class.new(seed_brokers, client_id: "TriXX: #{Socket.gethostname}")
    transactional_id = "TRIXX-#{Socket.gethostname}-#{@worker_id}"
    kafka_producer = kafka.producer(max_buffer_size: MAX_MESSAGE_BULK_COUNT, transactional: true, transactional_id: transactional_id)
    kafka_producer.init_transactions                                            # Should be called once before starting transactions

    # Loop for ever, check cancel criterial in threadhandling
    idle_sleep_time = 0
    retry_count_on_exception = 0                                                # limit retries
    while !@thread_mutex.synchronize { @stop_requested }
      begin
        ActiveRecord::Base.transaction do                                       # commit delete on database only if all messages are processed by kafka
          event_logs = read_event_logs_batch                                    # read bulk collection of messages from Event_Logs
          if event_logs.count > 0
            idle_sleep_time = 0                                                 # Reset sleep time for next idle time
            # Kafka transactions requires that deliver_messages is called within transaction. Otherwhise commit_transaction and abort_transaction will end up in Kafka::InvalidTxnStateError
            kafka_producer.transaction do                                       # make messages visible at kafka only if all messages of the batch are processed
              begin
                event_logs.each do |event_log|
                  @max_event_logs_id = event_log['id'] if event_log['id'] > @max_event_logs_id  # remember greatest processed ID to ensure lower IDs from pending transactions are also processed neartime

                  table = Rails.cache.fetch("Table_#{event_log['table_id']}", expires_in: 1.minutes) do
                    Table.find event_log['table_id']
                  end

                  kafka_producer.produce(prepare_message_from_event_log(event_log), topic: table.topic_to_use)   # Store messages in local collection
                end
                kafka_producer.deliver_messages                                 # bulk transfer of messages from collection to kafka
                delete_event_logs_batch(event_logs)
              rescue Exception => e
                msg = "TransferThread.process: within transaction with transactional_id = #{transactional_id}. Aborting transaction now.\n"
                msg << "Number of records to deliver = #{event_logs.count}"
                ExceptionHelper.log_exception(e, msg)
                raise
              end
            end
          else
            idle_sleep_time += 1 if idle_sleep_time < 60
          end
        end
        sleep idle_sleep_time if idle_sleep_time > 0                            # sleep some time outside transaction if no records are to be processed
        retry_count_on_exception = 0                                            # reset retry counter if successful processed
      rescue Exception => e
        if retry_count_on_exception < MAX_EXCEPTION_RETRY
          retry_count_on_exception += 1
          sleep 10                                                              # spend some time if problem is only temporary
          ExceptionHelper.log_exception(e, "TransferThread.process: Retrying after exception (#{retry_count_on_exception}. try)")
        else
          ExceptionHelper.log_exception(e, "TransferThread.process: Terminating thread now due to exception after #{MAX_EXCEPTION_RETRY} retries")
          raise
        end
      end
    end                                                                         # while
  rescue Exception => e
    ExceptionHelper.log_exception(e, "TransferThread.process: Terminating thread due to exception")
    raise
  ensure
    begin
      kafka_producer&.clear_buffer                                              # remove all pending (not processed by kafka) messages from producer buffer
      kafka_producer&.shutdown                                                  # free kafka connections
    rescue Exception => e
      ExceptionHelper.log_exception(e, "TransferThread.process: ensure (Kafka-disconnect)") # Ensure that following actions are processed in any case
    end
    Rails.logger.info "TransferThread(#{@worker_id}).process: stopped"
    ThreadHandling.get_instance.remove_from_pool(self)                          # unregister from threadpool
  end

  def stop_thread                                                               # called from main thread / job
    Rails.logger.info "TransferThread(#{@worker_id}).stop_thread: stop request executed"
    @thread_mutex.synchronize { @stop_requested = true }
  end

  private
  def read_event_logs_batch
    # Ensure that older IDs are processed first
    # only half of MAX_MESSAGE_BULK_COUNT is processed with newer IDs than last execution
    # the other half of MAX_MESSAGE_BULK_COUNT is reserved for older IDs from pending insert transactions that become visible later due to longer transaction duration
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      if Trixx::Application.partitioning
        event_logs = []
        # Iterate over partitions starting with oldest up to MAX_MESSAGE_BULK_COUNT records
        TableLess.select_all("SELECT Partition_Name, High_Value FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' AND Partition_Name != 'MIN' ")
            .sort_by{|x| x['high_value']}.each do |part|
          remaining_records = MAX_MESSAGE_BULK_COUNT - event_logs.count         # available space for more result records
          if remaining_records > 0                                              # add records from next partition to result
            event_logs.concat(TableLess.select_all("SELECT e.*, CAST(RowID AS VARCHAR2(30)) Row_ID FROM Event_Logs PARTITION (#{part['partition_name']}) e WHERE (ID < :max_id AND RowNum <= :remaining_records1) OR RowNum <= :remaining_records2 / 2 FOR UPDATE SKIP LOCKED",
                              {max_id: @max_event_logs_id, remaining_records1: remaining_records, remaining_records2: remaining_records })
            )
          end
        end
        event_logs
      else
        TableLess.select_all("SELECT e.*, CAST(RowID AS VARCHAR2(30)) Row_ID FROM Event_Logs e WHERE (ID < :max_id AND RowNum <= :max_message_bulk_count1) OR RowNum <= :max_message_bulk_count2 / 2 FOR UPDATE SKIP LOCKED",
                             {max_id: @max_event_logs_id, max_message_bulk_count1: MAX_MESSAGE_BULK_COUNT, max_message_bulk_count2: MAX_MESSAGE_BULK_COUNT }
        )
      end
    when 'SQLITE' then
      # Ensure that older IDs are processed first
      # only half of MAX_MESSAGE_BULK_COUNT is processed with newer IDs than last execution
      # the other half of MAX_MESSAGE_BULK_COUNT is reserved for older IDs from pending insert transactions that become visible later due to longer transaction duration
      TableLess.select_all("\
SELECT * FROM (SELECT * FROM Event_Logs WHERE ID < :max_id LIMIT #{MAX_MESSAGE_BULK_COUNT})
UNION
SELECT * FROM (SELECT * FROM Event_Logs LIMIT #{MAX_MESSAGE_BULK_COUNT / 2})",
                           {max_id: @max_event_logs_id}
      )
    else
      raise "Unsupported DB type '#{Trixx::Application.config.trixx_db_type}'"
    end
  end

  def delete_event_logs_batch(event_logs)
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      begin
        sql = "DELETE FROM Event_Logs WHERE RowID IN (SELECT Column_Value FROM TABLE(?))"
        jdbc_conn = ActiveRecord::Base.connection.raw_connection
        cursor = jdbc_conn.prepareStatement sql
        array = jdbc_conn.createARRAY("#{Trixx::Application.config.trixx_db_user.upcase}.ROWID_TABLE".to_java, event_logs.map{|e| e['row_id']}.to_java);
        cursor.setArray(1, array)
        result = cursor.executeUpdate
        raise "Error in TransferThread.delete_event_logs_batch: Only #{result} records hit by DELETE instead of #{event_logs.length}" if result != event_logs.length
      rescue Exception => e
        ExceptionHelper.log_exception(e, "Erroneous SQL:\n#{sql}")
        raise
      ensure
        cursor.close if defined? cursor
      end
    when 'SQLITE' then
      event_logs.each do |e|
        rows = TableLess.execute "DELETE FROM Event_Logs WHERE ID = :id", id: e['id']  # No known way for SQLite to execute in array binding
        raise "Error in TransferThread.delete_event_logs_batch: Only #{rows} records hit by DELETE instead of exactly one" if rows != 1
      end
    end
  end

  def prepare_message_from_event_log(event_log)
    "\
id: #{event_log['id']},
schema: '#{schema_name(event_log['schema_id'])}',
tablename: '#{table_name(event_log['table_id'])}',
operation: '#{long_operation_from_short(event_log['operation'])}',
timestamp: '#{timestamp_as_iso_string(event_log['created_at'])}',
#{event_log['payload']}
    "
  end

  private
  def long_operation_from_short(op)
    case op
    when 'I' then 'INSERT'
    when 'U' then 'UPDATE'
    when 'D' then 'DELETE'
    else raise "Unknown operation '#{op}'"
    end
  end

  # Cache schema names for repeated usage
  def schema_name(schema_id)
    unless @schemas_cache[schema_id]
      @schemas_cache[schema_id] = Schema.find(schema_id).name
    end
    @schemas_cache[schema_id]
  end

  # Cache table names for repeated usage
  def table_name(table_id)
    unless @tables_cache[table_id]
      @tables_cache[table_id] = Table.find(table_id).name
    end
    @tables_cache[table_id]
  end

  def timestamp_as_iso_string(timestamp)
    timestamp_as_time =
        case timestamp.class.name
        when 'String' then                                                      # assume structure like 2020-02-27 12:50:42, e.g. for SQLite without column type DATE
          Time.parse(timestamp)
        else
          timestamp
        end
    timestamp_as_time.strftime "%Y-%m-%dT%H:%M:%S,%6N%z"
  end
end



