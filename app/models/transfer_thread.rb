require 'kafka'
require 'kafka_mock'
require 'socket'

# preload classes to prevent from 'RuntimeError: Circular dependency detected while autoloading constant' if multiple threads start working simultaneously
require 'table_less'
require 'schema'
require 'table'
require 'exception_helper'

class TransferThread
  attr_reader :worker_id

  def self.create_worker(worker_id, options)
    worker = TransferThread.new(worker_id, options)
    thread = Thread.new do
      worker.process
    end
    thread.name = "TransferThread :#{worker_id}"
    worker
  rescue Exception => e
    ExceptionHelper.log_exception(e, "TransferThread.create_worker (#{worker_id})")
    raise
  end

  def initialize(worker_id, options)
    @worker_id = worker_id
    @max_transaction_size           = require_option(options, :max_transaction_size)     # Maximum number of message in transaction
    @max_message_bulk_count         = require_option(options, :max_message_bulk_count)   # Maximum number of message in buffer before delivery to kafka
    @max_buffer_bytesize            = require_option(options, :max_buffer_bytesize)      # Maximum size of Kafka buffer in bytes
    @start_time                     = Time.now
    @last_active_time               = nil                                       # timestamp of last transfer to kafka
    @total_messages_processed       = 0                                         # Total number of message processings, no matter whether successful or not
    @messages_processed_with_error  = 0                                         # Number of messages processing trials ending with error
    @max_message_size               = 0                                         # Max. size of single message in bytes
    @db_session_info                = 'set later in new thread'                 # Session ID etc.
    @thread                         = nil                                       # Reference to thread, set in new thread in method process
    @stop_requested                 = false
    @thread_mutex                   = Mutex.new                                 # Ensure access on instance variables from two threads
    @max_event_logs_id              = 0                                         # maximum processed id
    @transactional_id               = "TRIXX-#{Socket.gethostname}-#{@worker_id}" # Kafka transactional ID, must be unique per thread / Kafka connection
    @statistic_counter              = StatisticCounter.new
    @record_cache                   = {}                                        # cache subsequent access on Tables and Schemas, each Thread uses it's own cache
  end

  MAX_EXCEPTION_RETRY=3                                                         # max. number of retries after exception
  MAX_INIT_TRANSACTION_RETRY=3                                                  # max. number of retries after Kafka::ConcurrentTransactionError
  def process
    # process Event_Logs for  ID mod worker_count = worker_ID for update skip locked
    Rails.logger.info('TransferThread.process'){"New worker thread created with ID=#{@worker_id}"}
    @db_session_info = db_session_info                                          # Session ID etc., get information from within separate thread
    set_query_timeouts                                                     # ensure hanging sessions are cancelled sometimes
    @thread = Thread.current

    kafka_class = Trixx::Application.config.trixx_kafka_seed_broker == '/dev/null' ? KafkaMock : Kafka
    seed_brokers = Trixx::Application.config.trixx_kafka_seed_broker.split(',').map{|b| b.strip}

    kafka_options = {
        client_id: "TriXX: TRIXX-#{Socket.gethostname}",
        logger: Rails.logger
    }
    kafka_options[:ssl_ca_cert]                   = File.read(Trixx::Application.config.trixx_kafka_ssl_ca_cert)          if Trixx::Application.config.trixx_kafka_ssl_ca_cert
    kafka_options[:ssl_client_cert]               = File.read(Trixx::Application.config.trixx_kafka_ssl_client_cert)      if Trixx::Application.config.trixx_kafka_ssl_client_cert
    kafka_options[:ssl_client_cert_key]           = File.read(Trixx::Application.config.trixx_kafka_ssl_client_cert_key)  if Trixx::Application.config.trixx_kafka_ssl_client_cert_key
    kafka_options[:ssl_client_cert_key_password]  = Trixx::Application.config.trixx_kafka_ssl_client_cert_key_password    if Trixx::Application.config.trixx_kafka_ssl_client_cert_key_password

    kafka = kafka_class.new(seed_brokers, kafka_options)

    init_transactions_successfull = false
    init_transactions_retry_count = 0

    while !init_transactions_successfull

      begin
        kafka_producer = kafka.producer(
            max_buffer_size:      @max_message_bulk_count,
            max_buffer_bytesize:  @max_buffer_bytesize,
            transactional:        true,
            transactional_id:     @transactional_id
        )

        kafka_producer.init_transactions                                        # Should be called once before starting transactions
        init_transactions_successfull = true                                    # no exception raise
      rescue Exception => e
        kafka_producer&.shutdown                                                # clear existing producer
        log_exception(e, "kafka_producer.init_transactions: retry-count = #{init_transactions_retry_count}")
        if init_transactions_retry_count < MAX_INIT_TRANSACTION_RETRY
          sleep 1
          init_transactions_retry_count += 1
          @transactional_id << '-' if e.class == Kafka::ConcurrentTransactionError # change @transactional_id as workaround for Kafka::ConcurrentTransactionError
        else
          raise
        end
      end
    end

    # Loop for ever, check cancel criterial in threadhandling
    idle_sleep_time = 0
    event_logs = []                                                             # ensure variable is also known in exception handling
    retry_count_on_exception = 0                                                # limit retries
    while !@thread_mutex.synchronize { @stop_requested }
      begin
        ActiveRecord::Base.transaction do                                       # commit delete on database only if all messages are processed by kafka
          event_logs = read_event_logs_batch                                    # read bulk collection of messages from Event_Logs
          if event_logs.count > 0
            @total_messages_processed += event_logs.count
            @last_active_time = Time.now
            idle_sleep_time = 0                                                 # Reset sleep time for next idle time
            # Kafka transactions requires that deliver_messages is called within transaction. Otherwhise commit_transaction and abort_transaction will end up in Kafka::InvalidTxnStateError
            kafka_producer.transaction do                                       # make messages visible at kafka only if all messages of the batch are processed
              event_logs_slices = event_logs.each_slice(@max_message_bulk_count).to_a   # Produce smaller arrays for kafka processing
              Rails.logger.debug "Splitted #{event_logs.count} records in event_logs into #{event_logs_slices.count} slices"
              event_logs_slices.each do |event_logs_slice|
                Rails.logger.debug "Process event_logs_slice with #{event_logs_slice.count} records"
                begin
                  event_logs_slice.each do |event_log|
                    @max_event_logs_id = event_log['id'] if event_log['id'] > @max_event_logs_id  # remember greatest processed ID to ensure lower IDs from pending transactions are also processed neartime
                    table = table_cache(event_log['table_id'])
                    schema = schema_cache(table.schema_id)
                    kafka_message = prepare_message_from_event_log(event_log, schema, table)
                    topic = table.topic_to_use
                    begin
                      @statistic_counter.increment(table.id, event_log['operation'])
                      kafka_producer.produce(kafka_message, topic: topic, key: event_log['key']) # Store messages in local collection
                    rescue Kafka::BufferOverflow => e
                      Rails.logger.warn "#{e.class} #{e.message}: max_buffer_size = #{@max_message_bulk_count}, max_buffer_bytesize = #{@max_buffer_bytesize}, current message value size = #{kafka_message.bytesize}, topic = #{topic}, schema = #{schema.name}, table = #{table.name}"
                      reduce_step = @max_message_bulk_count / 10                  # Reduce by 10%
                      if @max_message_bulk_count > reduce_step + 1
                        @max_message_bulk_count -= reduce_step
                        Trixx::Application.config.trixx_kafka_max_bulk_count = @max_message_bulk_count  # Ensure reduced value is valid also for new TransferThreads
                        Rails.logger.warn "Reduce max_buffer_size by #{reduce_step} to #{@max_message_bulk_count} to prevent this situation"
                      end
                      raise                                                       # Ensure transaction is rolled back an retried
                    end
                  end
                  kafka_producer.deliver_messages                                 # bulk transfer of messages from collection to kafka
                  delete_event_logs_batch(event_logs_slice)                     # delete the part in DB currently processed by kafka
                rescue Kafka::MessageSizeTooLarge => e
                  Rails.logger.warn "#{e.class} #{e.message}: max_buffer_size = #{@max_message_bulk_count}, max_buffer_bytesize = #{@max_buffer_bytesize}"
                  fix_message_size_too_large(kafka, event_logs_slice)
                  raise                                                       # Ensure transaction is rolled back an retried
                rescue Exception => e
                  msg = "TransferThread.process #{@worker_id}: within transaction with transactional_id = #{@transactional_id}. Aborting transaction now.\n"
                  msg << "Number of records to deliver to kafka = #{event_logs_slice.count}"
                  log_exception(e, msg)
                  raise
                end
              end
            end                                                                 # kafka_producer.transaction do
          else
            idle_sleep_time += 1 if idle_sleep_time < 60
          end
        end                                                                     # ActiveRecord::Base.transaction do
        sleep_and_watch(idle_sleep_time) if idle_sleep_time > 0                 # sleep some time outside transaction if no records are to be processed
        retry_count_on_exception = 0                                            # reset retry counter if successful processed
        @statistic_counter.flush_success                                        # Mark cumulated statistics as success and write to disk
      rescue Exception => e
        kafka_producer.clear_buffer                                             # remove all pending (not processed by kafka) messages from producer buffer
        @messages_processed_with_error +=  event_logs.count
        @statistic_counter.flush_failure                                        # Mark cumulated statistics as failure and write to disk
        if retry_count_on_exception < MAX_EXCEPTION_RETRY
          retry_count_on_exception += 1
          sleep_and_watch 10                                                    # spend some time if problem is only temporary
          log_exception(e, "TransferThread.process #{@worker_id}: Retrying after exception (#{retry_count_on_exception}. try)")
        else
          log_exception(e, "TransferThread.process #{@worker_id}: Terminating thread now due to exception after #{MAX_EXCEPTION_RETRY} retries")
          raise
        end
      end
    end                                                                         # while
  rescue Exception => e
    log_exception(e, "TransferThread.process #{@worker_id}: Terminating thread due to exception")
    raise
  ensure
    begin
      kafka_producer&.clear_buffer                                              # remove all pending (not processed by kafka) messages from producer buffer
      kafka_producer&.shutdown                                                  # free kafka connections
    rescue Exception => e
      log_exception(e, "TransferThread.process #{@worker_id}: ensure (Kafka-disconnect)") # Ensure that following actions are processed in any case
    end
    Rails.logger.info "TransferThread.process #{@worker_id}: stopped"
    Rails.logger.info thread_state
    ThreadHandling.get_instance.remove_from_pool(self)                          # unregister from threadpool

    # Return Connection to pool only if Application retains, otherwhise 'NameError: uninitialized constant ActiveRecord::Connection' is raised in test
    if !Rails.env.test?                                                         # not for test because threads have all the same DB connection in test
      ActiveRecord::Base.connection_handler.clear_active_connections!           # Ensure that connections are freed in connection pool
    end
  end

  def stop_thread                                                               # called from main thread / job
    Rails.logger.info "TransferThread.stop_thread #{@worker_id}: stop request executed"
    @thread_mutex.synchronize { @stop_requested = true }
  end

  # get Hash with current state info for thread, used e.g. for health check
  def thread_state
    {
        worker_id:                      @worker_id,
        thread_id:                      @thread&.object_id,
        transactional_id:               @transactional_id,
        db_session_info:                @db_session_info,
        start_time:                     @start_time,
        last_active_time:               @last_active_time,
        max_message_size:               @max_message_size,
        max_event_logs_id:              @max_event_logs_id,
        successful_messages_processed:  @total_messages_processed - @messages_processed_with_error,
        message_processing_errors:      @messages_processed_with_error,
        stacktrace:                     @thread&.backtrace
    }
  end

  private
  def read_event_logs_batch
    # Ensure that older IDs are processed first
    # only half of @max_transaction_size is processed with newer IDs than last execution
    # the other half of @max_transaction_size is reserved for older IDs from pending insert transactions that become visible later due to longer transaction duration
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      if Trixx::Application.partitioning
        event_logs = []
        # Iterate over partitions starting with oldest up to @max_transaction_size records
        TableLess.select_all("SELECT Partition_Name, High_Value FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' AND Partition_Name != 'MIN' ")
            .sort_by{|x| x['high_value']}.each do |part|
          remaining_records = @max_transaction_size - event_logs.count          # available space for more result records
          if remaining_records > 0                                              # add records from next partition to result
            # First step: look for records with smaller ID than largest of lst run (older records)
            event_logs.concat(TableLessOracle.select_all_limit("SELECT e.*, CAST(RowID AS VARCHAR2(30)) Row_ID
                                                                FROM   Event_Logs PARTITION (#{part['partition_name']}) e
                                                                WHERE  e.ID < :max_id
                                                                FOR UPDATE SKIP LOCKED",
                                                               {max_id: @max_event_logs_id}, fetch_limit: remaining_records, query_timeout: Trixx::Application.config.trixx_db_query_timeout
            ))
            remaining_records = @max_transaction_size - event_logs.count        # available space for more result records
            if remaining_records > 0                                            # fill rest of buffer with all unlocked records not read by the first SQL (ID>=max_id)
              event_logs.concat(TableLessOracle.select_all_limit("SELECT e.*, CAST(RowID AS VARCHAR2(30)) Row_ID
                                                                FROM   Event_Logs PARTITION (#{part['partition_name']}) e
                                                                WHERE  e.ID >= :max_id
                                                                FOR UPDATE SKIP LOCKED",
                                                                 {max_id: @max_event_logs_id}, fetch_limit: remaining_records, query_timeout: Trixx::Application.config.trixx_db_query_timeout
              ))
            end
          end
        end
        event_logs
      else
        TableLess.select_all("SELECT e.*, CAST(RowID AS VARCHAR2(30)) Row_ID FROM Event_Logs e WHERE (ID < :max_id AND RowNum <= :max_message_bulk_count1) OR RowNum <= :max_message_bulk_count2 / 2 FOR UPDATE SKIP LOCKED",
                             {max_id: @max_event_logs_id, max_message_bulk_count1: @max_transaction_size, max_message_bulk_count2: @max_transaction_size }
        )
      end
    when 'SQLITE' then
      # Ensure that older IDs are processed first
      # only half of @max_transaction_size is processed with newer IDs than last execution
      # the other half of @max_transaction_size is reserved for older IDs from pending insert transactions that become visible later due to longer transaction duration
      TableLess.select_all("\
SELECT * FROM (SELECT * FROM Event_Logs WHERE ID < :max_id LIMIT #{@max_transaction_size})
UNION
SELECT * FROM (SELECT * FROM Event_Logs LIMIT #{@max_transaction_size / 2})",
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
        sql = "DELETE /*+ ROWID */ FROM Event_Logs WHERE RowID IN (SELECT Column_Value FROM TABLE(?))"
        jdbc_conn = ActiveRecord::Base.connection.raw_connection
        cursor = jdbc_conn.prepareStatement sql
        ActiveSupport::Notifications.instrumenter.instrument('sql.active_record', sql: sql, name: "TransferThread DELETE with #{event_logs.count} records") do
          array = jdbc_conn.createARRAY("#{Trixx::Application.config.trixx_db_user.upcase}.ROWID_TABLE".to_java, event_logs.map{|e| e['row_id']}.to_java);
          cursor.setArray(1, array)
          result = cursor.executeUpdate
          if result != event_logs.length
            raise "Error in TransferThread.delete_event_logs_batch: Only #{result} records hit by DELETE instead of #{event_logs.length}."
          end
        end
      rescue Exception => e
        log_exception(e, "Erroneous SQL:\n#{sql}")
        raise
      ensure
        cursor.close if defined? cursor && !cursor.nil?
      end
    when 'SQLITE' then
      event_logs.each do |e|
        rows = TableLess.execute "DELETE FROM Event_Logs WHERE ID = :id", id: e['id']  # No known way for SQLite to execute in array binding
        raise "Error in TransferThread.delete_event_logs_batch: Only #{rows} records hit by DELETE instead of exactly one" if rows != 1
      end
    end
  end

  def prepare_message_from_event_log(event_log, schema, table)
    msg = "\
id: #{event_log['id']},
schema: '#{schema.name}',
tablename: '#{table.name}',
operation: '#{long_operation_from_short(event_log['operation'])}',
timestamp: '#{timestamp_as_iso_string(event_log['created_at'])}',
#{event_log['payload']}
    "
    @max_message_size = msg.bytesize if msg.bytesize > @max_message_size
    msg
  end

  def long_operation_from_short(op)
    case op
    when 'I' then 'INSERT'
    when 'U' then 'UPDATE'
    when 'D' then 'DELETE'
    else raise "Unknown operation '#{op}'"
    end
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

  def db_session_info
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      TableLess.select_one "SELECT SID||','||Serial# FROM v$Session WHERE SID=SYS_CONTEXT('USERENV', 'SID')"
    else '< not implemented >'
    end
  end

  def sleep_and_watch(sleeptime)
    1.upto(sleeptime) do
      sleep(1)
      if @thread_mutex.synchronize { @stop_requested }                          # Cancel sleep if stop requested
        return                                                                  # return immediate
      end
    end
  end

  # fix Exception Kafka::MessageSizeTooLarge
  def fix_message_size_too_large(kafka, event_logs)

    # get max. message value sizes per topic
    topic_info = {}
    event_logs.each do |event_log|
      table = table_cache(event_log['table_id'])
      schema = schema_cache(table.schema_id)
      kafka_message = prepare_message_from_event_log(event_log, schema, table)
      topic = table.topic_to_use

      topic_info[topic] = { max_message_value_size: 0} unless topic_info.has_key?(topic)
      topic_info[topic][:max_message_value_size] = kafka_message.bytesize if kafka_message.bytesize > topic_info[topic][:max_message_value_size]
    end

    # get current max.message.byte per topic
    topic_info.each do |key, value|
      current_max_message_bytes = kafka.describe_topic(key, ['max.message.bytes'])['max.message.bytes']

      Rails.logger.info "Topic='#{key}', largest msg size in buffer = #{value[:max_message_value_size]}, topic-config max.message.bytes = #{current_max_message_bytes}"

      if current_max_message_bytes && value[:max_message_value_size] > current_max_message_bytes.to_i * 0.8
        # new max.message.bytes based on current value or largest msg size, depending on the larger one
        new_max_message_bytes = value[:max_message_value_size]
        new_max_message_bytes = current_max_message_bytes.to_i if current_max_message_bytes.to_i > new_max_message_bytes
        new_max_message_bytes = (new_max_message_bytes * 1.2).to_i              # Enlarge by 20%

        response = kafka.alter_topic(key, "max.message.bytes" => new_max_message_bytes.to_s)
        unless response.nil?
          Rails.logger.error "#{response.class} #{response}:"
        else
          Rails.logger.warn "Enlarge max.message.bytes for topic #{key} from #{current_max_message_bytes} to #{new_max_message_bytes} to prevent Kafka::MessageSizeTooLarge"
        end
      end
    end
  end

  def require_option(options, option_name)
    raise "Option ':#{option_name}' required!" unless options[option_name]
    options[option_name]
  end

  def log_exception(exception, message)
    ExceptionHelper.log_exception(exception, "#{message}\n#{thread_state}")
  end

  def schema_cache(schema_id)
    check_record_cache_for_aging
    key = "Schema #{schema_id}"
    unless @record_cache.has_key? key
      @record_cache[key] = Schema.find schema_id
    end
    @record_cache[key]
  end

  def table_cache(schema_id)
    check_record_cache_for_aging
    key = "Table #{schema_id}"
    unless @record_cache.has_key? key
      @record_cache[key] = Table.find schema_id
    end
    @record_cache[key]
  end

  RECORD_CACHE_REFRESH_CYCLE = 60                                               # Number of seconds between cache refeshes
  def check_record_cache_for_aging
    unless @record_cache.has_key? :first_access
      @record_cache[:first_access] = Time.now
    end
    if @record_cache[:first_access] + RECORD_CACHE_REFRESH_CYCLE < Time.now
      Rails.logger.debug "TransferThread.check_record_cache_for_aging: Reset record cache after#{RECORD_CACHE_REFRESH_CYCLE} seconds"
      @record_cache = {}                                                        # reset record cache after 1 minute to reread possibly changed topic names
    end
  end

  def set_query_timeouts
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      raw_conn = ActiveRecord::Base.connection.raw_connection
      # Ensure that hanging SQL executions are cancelled after timeout
      raw_conn.setNetworkTimeout(java.util.concurrent.Executors.newSingleThreadExecutor, Trixx::Application.config.trixx_db_query_timeout * 2 * 1000)
    end
  end
end



