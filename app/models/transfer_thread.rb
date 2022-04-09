require 'kafka'
require 'kafka_mock'
require 'socket'

# preload classes to prevent from 'RuntimeError: Circular dependency detected while autoloading constant' if multiple threads start working simultaneously
require 'database'
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
    thread.report_on_exception = false                                          # don't report the last exception in thread because it is already logged by thread itself
    worker
  rescue Exception => e
    ExceptionHelper.log_exception(e, 'TransferThread.create_worker', additional_msg: "Worker ID = #{worker_id}")
    raise
  end

  def initialize(worker_id, options)
    @worker_id = worker_id
    @max_transaction_size           = require_option(options, :max_transaction_size)     # Maximum number of message in transaction
    @max_message_bulk_count         = require_option(options, :max_message_bulk_count)   # Maximum number of message in buffer before delivery to kafka
    @max_buffer_bytesize            = require_option(options, :max_buffer_bytesize)      # Maximum size of Kafka buffer in bytes
    # Maximum distance between first and greatest ID to ensure that number of read events is less than maximum number of messages to read at once
    # this value is dynamically adjusted at runtime so that the number of read records is as high as possible but below @max_transaction_size
    @max_sorted_id_distances        = {}                                        # This values are maintained by increase/decrease_max_sorted_id_distance and get_max_sorted_id_distance
    @start_time                     = Time.now
    @last_active_time               = nil                                       # timestamp of last transfer to kafka
    @messages_processed_successful  = 0                                         # Number of successful message processings
    @messages_processed_with_error  = 0                                         # Number of messages processing trials ending with error
    @max_message_size               = 0                                         # Max. size of single message in bytes
    @db_session_info                = 'set later in new thread'                 # Session ID etc.
    @thread                         = nil                                       # Reference to thread, set in new thread in method process
    @stop_requested                 = false
    @thread_mutex                   = Mutex.new                                 # Ensure access on instance variables from two threads
    @max_event_logs_id              = 0                                         # maximum processed id over all Event_Logs-records of thread
    @max_key_event_logs_id          = get_max_event_logs_id_from_sequence       # maximum processed id over all Event_Logs-records of thread with key != NULL, initialized with max value
    @transactional_id               = "MOVEX-CDC-#{Socket.gethostname}-#{@worker_id}" # Kafka transactional ID, must be unique per thread / Kafka connection
    @statistic_counter              = StatisticCounter.new
    @record_cache                   = {}                                        # cache subsequent access on Tables and Schemas, each Thread uses it's own cache
    @cached_max_event_logs_seq_id   = @max_key_event_logs_id                    # last known max value from sequence, refreshed by get_max_event_logs_id_from_sequence if required
    @kafka_producer                 = nil                                       # initialized later
    @last_read_events               = 0                                         # number of event_log records read at last read rom event_logs
    @last_scanned_partitions        = 0                                         # number of partitions scanned at last read rom event_logs
    @concurrent_tx_retry_delay_ms   = 1                                         # Amount of delay before retry at Kafka::ConcurrentTransactionError, increased if not sufficient
  end

  # Do processing in a separate Thread
  def process
    # process Event_Logs for  ID mod worker_count = worker_ID for update skip locked
    Rails.logger.info('TransferThread.process'){"New worker thread created with ID=#{@worker_id}, Thread-ID=#{Thread.current.object_id}"}
    Database.set_application_info("worker #{@worker_id}/process")
    @db_session_info = Database.db_session_info                                          # Session ID etc., get information from within separate thread
    Database.set_current_session_network_timeout(timeout_seconds: MovexCdc::Application.config.db_query_timeout * 2) # ensure hanging sessions are cancelled sometimes
    @thread = Thread.current

    @kafka_producer = create_kafka_producer                                     # Initial creation

    # Loop for ever, check cancel criteria in ThreadHandling
    idle_sleep_time = 0
    event_logs = []                                                             # ensure variable is also known in exception handling
    while !@thread_mutex.synchronize { @stop_requested }
      ActiveRecord::Base.transaction do                                         # commit delete on database only if all messages are processed by kafka
        event_logs = read_event_logs_batch                                      # read bulk collection of messages from Event_Logs
        @last_read_events = event_logs.count                                    # remember for health check
        if event_logs.count > 0
          @last_active_time = Time.now
          process_event_logs_divide_and_conquer(event_logs)
          @statistic_counter.flush                                              # Write cumulated statistics to singleton memory only if processing happened
        end
        idle_sleep_time = calc_idle_sleep_time(processed_events_count: event_logs.count, current_idle_sleep_time: idle_sleep_time)
      end                                                                       # ActiveRecord::Base.transaction do
      sleep_and_watch(idle_sleep_time) if idle_sleep_time > 0                   # sleep some time outside transaction if no records are to be processed
    end
  rescue Exception => e
    log_exception_with_worker_state(e, 'TransferThread.process',  message: "#{@worker_id}: Terminating thread due to exception")
  ensure
    begin
      @kafka_producer&.shutdown                                                 # free kafka connections before terminating Thread
    rescue Exception => e
      ExceptionHelper.log_exception(e, 'TransferThread.process', additional_msg: "Worker-ID = #{@worker_id}: ensure (Kafka-disconnect)") # Ensure that following actions are processed in any case
    end
    begin
      @statistic_counter.flush                                                    # Write cumulated statistics to singleton memory
      Rails.logger.info "TransferThread.process #{@worker_id}: stopped"
      Rails.logger.info JSON.pretty_generate(thread_state(without_stacktrace: true))
      ThreadHandling.get_instance.remove_from_pool(self)                          # unregister from threadpool

      # Return Connection to pool only if Application retains, otherwhise 'NameError: uninitialized constant ActiveRecord::Connection' is raised in test
      if !Rails.env.test?                                                         # not for test because threads have all the same DB connection in test
        ActiveRecord::Base.connection_handler.clear_active_connections!           # Ensure that connections are freed in connection pool
      end
    rescue Exception => e
      ExceptionHelper.log_exception(e, 'TransferThread.process', additional_msg: "Worker-ID = #{@worker_id}: remaining ensure ") #
      raise                                                                     # this raise may not be catched because it is the last operation of this thread
    end
  end # process

  def stop_thread                                                               # called from main thread / job
    Rails.logger.info "TransferThread.stop_thread #{@worker_id}: stop request forced"
    @thread_mutex.synchronize { @stop_requested = true }
  end

  # get Hash with current state info for thread, used e.g. for health check
  def thread_state(options = {})
    retval = {
      cached_max_event_logs_seq_id:   @cached_max_event_logs_seq_id,
      db_session_info:                @db_session_info,
      last_active_time:               @last_active_time,
      last_read_events:               @last_read_events,
      last_scanned_partitions:        @last_scanned_partitions,
      max_event_logs_id:              @max_event_logs_id,
      max_key_event_logs_id:          @max_key_event_logs_id,
      max_message_size:               @max_message_size,
      max_sorted_id_distances:        @max_sorted_id_distances,
      message_processing_errors:      @messages_processed_with_error,
      start_time:                     @start_time,
      successful_messages_processed:  @messages_processed_successful,
      thread_id:                      @thread&.object_id,
      transactional_id:               @transactional_id,
      worker_id:                      @worker_id,
    }
    retval[:stacktrace] = @thread&.backtrace unless options[:without_stacktrace]
    retval
  end

  private

  MAX_INIT_TRANSACTION_RETRY=3                                                  # max. number of retries after Kafka::ConcurrentTransactionError
  # Connect to Kafka and create producer instance
  def create_kafka_producer
    kafka = KafkaHelper.connect_kafka                                           # gets instance of class Kafka

    init_transactions_successfull = false
    init_transactions_retry_count = 0

    while !init_transactions_successfull

      begin
        producer_options = {
            max_buffer_size:      @max_message_bulk_count,
            max_buffer_bytesize:  @max_buffer_bytesize,
            transactional:        true,
            transactional_id:     @transactional_id,
            max_retries: 0                                                      # ensure producer does not sleep between retries, setting > 0 will reduce MOVEX CDC's throughput
        }

        producer_options[:compression_codec]             = MovexCdc::Application.config.kafka_compression_codec.to_sym        if MovexCdc::Application.config.kafka_compression_codec != 'none'

        kafka_producer = kafka.producer(producer_options)

        kafka_producer.init_transactions                                        # Should be called once before starting transactions
        init_transactions_successfull = true                                    # no exception raise
      rescue Exception => e
        kafka_producer&.shutdown                                                # clear existing producer
        ExceptionHelper.log_exception(e, 'kafka_producer.init_transactions', additional_msg: "retry-count = #{init_transactions_retry_count}")
        if init_transactions_retry_count < MAX_INIT_TRANSACTION_RETRY
          sleep 1
          init_transactions_retry_count += 1
          @transactional_id << '-' if e.class == Kafka::ConcurrentTransactionError # change @transactional_id as workaround for Kafka::ConcurrentTransactionError
        else
          raise
        end
      end
    end
    kafka_producer
  end

  # Cancel previous producer and recreate again
  def reset_kafka_producer
    @kafka_producer&.shutdown                                                   # free kafka connections of current producer if != nil
    @kafka_producer = create_kafka_producer                                     # get fresh producer
  end

  # Process the event_logs array within the AR transaction
  # Method is called recursive on error until event_logs.size = 1
  def process_event_logs_divide_and_conquer(event_logs, recursive_depth = 0)
    return if event_logs.count == 0                                             # No useful processing of empty arrays, should not occur
    event_logs.each do |e|
      @statistic_counter.increment(e['table_id'], e['operation'], :events_d_and_c_retries) if recursive_depth > 0
    end

    kafka_transaction_successful = false                                        # Flag that ensures delete_event_logs_batch is called only if process_kafka_transaction was successful

    begin
      process_kafka_transaction(event_logs)
      kafka_transaction_successful = true                                       # delete_event_logs_batch can be called
    rescue Exception => e
      Rails.logger.info('TransferThread.process_event_logs_divide_and_conquer'){"Divide & conquer with current array size = #{event_logs.count}, recursive depth = #{recursive_depth} due to #{e.class}:#{e.message}"}
      reset_kafka_producer                                                      # After transaction error in Kafka the current producer ends up in Kafka::InvalidTxnStateError if trying to continue with begin_transaction
      if event_logs.count > 1                                                   # divide remaining event_logs in smaller parts
        max_slice_size = event_logs.count / 10                                  # divide the array size by x each time an error occurs
        max_slice_size = 1 if max_slice_size < 1                                # ensure minimum size of single array
        event_logs.each_slice(max_slice_size).to_a.each do |slice|
          process_event_logs_divide_and_conquer(slice, recursive_depth + 1)     # Process recursively single parts of previous array
        end
      else                                                                      # single erroneous event isolated now
        process_single_erroneous_event_log(event_logs[0], e)
      end
    end

    begin
      delete_event_logs_batch(event_logs) if kafka_transaction_successful       # delete the events that are successfully processed in previous kafka transaction
    rescue Exception => e
      ExceptionHelper.log_exception(e, 'TransferThread.process_event_logs_divide_and_conquer', additional_msg: "delete_event_logs_batch failed. This should never happen and leads to multiple processing of events to Kafka.")
      event_logs_debug_info(event_logs)
      raise
    end

  end



  def read_event_logs_batch
    event_logs = []
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      if MovexCdc::Application.partitioning?
        # Iterate over partitions starting with oldest up to @max_transaction_size records
        Rails.logger.debug "TransferThread.read_event_logs_batch: Start iterating over partitions"
        partitions = Database.select_all("SELECT Partition_Name, High_Value
                                          FROM   User_Tab_Partitions
                                          WHERE  Table_Name = 'EVENT_LOGS' AND Partition_Position > 1 /* Do not check the first non-interval partition */
                                         ").sort_by{|x| x['high_value']}
        Rails.logger.debug "TranferThread.read_event_logs_batch: Found #{partitions.count} partitions to scan"
        @last_scanned_partitions = 0
        partitions.each_index do |i|
          remaining_records = @max_transaction_size - event_logs.count          # available space for more result records
          if remaining_records > 0 # Skip next partitions if already read enough records
            event_logs.concat(read_event_logs_steps(max_records_to_read:  remaining_records,
                                                    partition_name:       partitions[i]['partition_name'],
                                                    last_partition:       i == partitions.count-1
                              )
            )
            @last_scanned_partitions += 1                                       # remember for health check
          end
        end
        housekeep_max_sorted_id_distance(partitions.map {|p| p['partition_name']})
      else                                                                      # non-partitioned Oracle table
        event_logs.concat(read_event_logs_steps(max_records_to_read: @max_transaction_size))
      end

      # adjust cached value to reality for next read if not maximum number of records has been read
      @cached_max_event_logs_seq_id = get_max_event_logs_id_from_sequence if event_logs.count < @max_transaction_size

    when 'SQLITE' then
      event_logs.concat(read_event_logs_steps(max_records_to_read: @max_transaction_size))
    else
      raise "Unsupported DB type '#{MovexCdc::Application.config.db_type}'"
    end
    event_logs.sort_by! {|e| e['id']}                                           # ensure original order of event creation
    event_logs.each do |e|
      @statistic_counter.increment(e['table_id'], e['operation'], :events_delayed_retries) if e['retry_count'] > 0
    end
    event_logs
  end

  # read event_logs with multiple selects
  # Steps for processing are:
  # 1. read records with key value hash related to this worker (modulo). Each worker is reponsible to process a number of keys (identified by modulo) to ensure in order processing to Kafka
  # 2. look for records without key value and with smaller ID than largest of last run (older records)
  # 3. look for records without key value and with larger ID than largest of last run (newer records)
  def read_event_logs_steps(max_records_to_read:, partition_name: nil, last_partition: true)
    result = []
    # 1. read records with key value hash related to this worker (modulo). Each worker is reponsible to process a number of keys (identified by modulo) to ensure in order processing to Kafka
    # Condition to identify events with msg_key for which this worker instance is reponsible for processing
    msg_key_filter_condition = case MovexCdc::Application.config.db_type
                               when 'ORACLE' then "Msg_Key IS NOT NULL AND MOD(ORA_HASH(Msg_Key, 1000000), #{MovexCdc::Application.config.initial_worker_threads}) = :worker_id"
                               when 'SQLITE' then "Msg_Key IS NOT NULL AND LENGTH(Msg_Key) % #{MovexCdc::Application.config.initial_worker_threads} = :worker_id" # LENGTH as workaround for not existing hash function
                               end



    Rails.logger.debug "TransferThread.read_event_logs_steps: Start processing with @max_key_event_logs_id = #{@max_key_event_logs_id}, max_sorted_id_distance = #{get_max_sorted_id_distance(partition_name)}, max_records_to_read = #{max_records_to_read}, @cached_max_event_logs_seq_id = #{@cached_max_event_logs_seq_id}"
    key_result = []                                                             # ensure existence of variable outside loop
    max_processed_key_event_logs_id = 0                                         # Maximum ID already selected by previous loop
    max_key_event_logs_id_used_for_sql = nil                                    # initialize auto variable to be set in local block
    loop_count = 0                                                              # observe number of loops to prevent infinite loops
    loop do                                                                     # loop until all records read or max_records_to_read reached
      loop_count += 1
      loop do                                                                   # loop until records read at once are < @max_transaction_size to ensure sorted order
        loop_count += 1                                                         # count inner loop like outer loop in sum

        if loop_count > 1000                                                    # protect against infinite loop
          msg = "TransferThread.read_event_logs_steps: risk of infinite loop. Cancelled now! @max_key_event_logs_id = #{@max_key_event_logs_id}, max_sorted_id_distance = #{get_max_sorted_id_distance(partition_name)}, max_records_to_read = #{max_records_to_read}, result.count = #{result.count}"
          Rails.logger.error msg
          raise msg
        end

        max_key_event_logs_id_used_for_sql = @max_key_event_logs_id             # remember the value used for SQL for later comparison in break clause
        # @max_transaction_size instead of max_records_to_read is the limit here to ensure even distances also if events from previous and next partition are combined
        key_result = read_event_logs_single(fetch_limit:      @max_transaction_size,
                                            filter:           "ID > :min_ID AND ID < :max_id AND #{msg_key_filter_condition}",
                                            params:           {min_id: max_processed_key_event_logs_id, max_id: max_key_event_logs_id_used_for_sql + get_max_sorted_id_distance(partition_name), worker_id: @worker_id},
                                            partition_name:   partition_name
        )

        break if key_result.count < @max_transaction_size                       # it is ensured that no unread records are remaining with key IS NOT NULL and ID < @max_key_event_logs_id (sorted order ensured)

        # Discard the read result and prepare next loop execution to reach the limit key_result.count < @max_transaction_size and ensure processing of all smaller IDs
        if get_max_sorted_id_distance(partition_name) >= @max_transaction_size  # Possible to read more than @max_transaction_size records
          decrease_max_sorted_id_distance(partition_name, 2) # Reduce the distance to ensure all smaller records are catched at next run
          Rails.logger.debug "TransferThread.read_event_logs_steps: max_sorted_id_distance decreased to #{get_max_sorted_id_distance(partition_name)} #{"for partition #{partition_name} " if partition_name}because the number of read events should be less than #{key_result.count}"
        else                                                                    # There must exist more records in table with id < @max_key_event_logs_id + max_sorted_id_distance than @max_transaction_size
          @max_key_event_logs_id = get_min_key_id(msg_key_filter_condition, {worker_id: @worker_id}, partition_name) - 1 # Start next run with smaller max. id but ensure to catch at least one record
          Rails.logger.debug "TransferThread.read_event_logs_steps: @max_key_event_logs_id decreased to #{@max_key_event_logs_id} because there are still to much records below @max_key_event_logs_id + max_sorted_id_distance (#{get_max_sorted_id_distance(partition_name)})#{" for partition #{partition_name}" if partition_name}"
        end
      end                                                                       # inner loop

      key_result.each {|r| @max_key_event_logs_id = r['id'] if r['id'] > @max_key_event_logs_id }  # remember the highest ID for next run
      max_processed_key_event_logs_id = @max_key_event_logs_id
      result.concat key_result

      # break loop if max. amount of record is reached. It is sufficient if more than max_records_to_read are read even if select was done with full @max_transaction_size
      if result.count >= max_records_to_read
        Rails.logger.debug "TransferThread.read_event_logs_steps: break the loop of step 1 because number of read records (#{result.count}) > max_records_to_read (#{max_records_to_read})"
        break
      end

      # break loop if all possible values of ID have been covered by previous SQL
      if max_key_event_logs_id_used_for_sql + get_max_sorted_id_distance(partition_name) > @cached_max_event_logs_seq_id
        Rails.logger.debug "TransferThread.read_event_logs_steps: break the loop of step 1 because max_key_event_logs_id_used_for_sql (#{max_key_event_logs_id_used_for_sql}) + get_max_sorted_id_distance('#{partition_name}') (#{get_max_sorted_id_distance(partition_name)}) > @cached_max_event_logs_seq_id (#{@cached_max_event_logs_seq_id})"
        break
      end

      # Enlarge max_sorted_id_distance up to maximum if less than 1/2 of @max_transaction_size is used, but don't increase distance for possibly empty older partitions
      if key_result.count < @max_transaction_size / 2
        Rails.logger.debug "TransferThread.read_event_logs_steps: Check for increasing of max_sorted_id_distance (#{get_max_sorted_id_distance(partition_name)})#{" for partition #{partition_name}" if partition_name}, @max_key_event_logs_id = #{@max_key_event_logs_id}, @cached_max_event_logs_seq_id = #{@cached_max_event_logs_seq_id}"

        # if old distance is below max known ID then increase distance
        if @max_key_event_logs_id + get_max_sorted_id_distance(partition_name) <= @cached_max_event_logs_seq_id
          increase_factor = 10                                                  # Default if key_result.count == 0
          if key_result.count > 0
            increase_factor = 1 + (@max_transaction_size/2.0 - key_result.count) * 2 / (@max_transaction_size/2.0) # should result in scored value from 1 up to 3
          end
          increase_max_sorted_id_distance(partition_name, increase_factor)
          Rails.logger.debug "TransferThread.read_event_logs_steps: max_sorted_id_distance increased by factor #{increase_factor} to #{get_max_sorted_id_distance(partition_name)}#{" for partition #{partition_name}" if partition_name}"
        end

      end
    end                                                                         # outer loop


    # 2. look for records without key value and with smaller ID than largest of last run (older records)
    remaining_records = max_records_to_read - result.count                      # available space for more result records
    result.concat read_event_logs_single(fetch_limit:     remaining_records,
                                         filter:          "Msg_Key IS NULL AND ID < :max_id",
                                         params:          {max_id: @max_event_logs_id},
                                         partition_name:  partition_name
                  )

    # 3. look for records without key value and with larger ID than largest of last run (newer records)
    remaining_records = max_records_to_read - result.count                      # available space for more result records
    # fill rest of buffer with all unlocked records not read by the first SQL (ID>=max_id)
    result.concat read_event_logs_single(fetch_limit:     remaining_records,
                                         filter:          "Msg_Key IS NULL AND ID >= :max_id",
                                         params:          {max_id: @max_event_logs_id},
                                         partition_name:  partition_name
                  )

    result
  end

  # Do SQL select for given conditions
  def read_event_logs_single(fetch_limit:, filter:, params:, partition_name:)
    if fetch_limit > 0
      case MovexCdc::Application.config.db_type
      when 'ORACLE' then
        # each error retry enlarges the delay before next retry by factor 3
        DatabaseOracle.select_all_limit("SELECT e.*, CAST(RowID AS VARCHAR2(30)) Row_ID
                                                                FROM   Event_Logs#{" PARTITION (#{partition_name})" if partition_name} e
                                                                WHERE  #{filter}
                                                                AND    (Retry_Count = 0 OR Last_Error_Time + (#{MovexCdc::Application.config.error_retry_start_delay} * POWER(3, Retry_Count-1))/86400 < CAST(SYSTIMESTAMP AS TIMESTAMP)) /* Compare last_error_time without timezone impact */
                                                                FOR UPDATE SKIP LOCKED",
                                        params, fetch_limit: fetch_limit, query_timeout: MovexCdc::Application.config.db_query_timeout
        )
      when 'SQLITE' then
        Database.select_all("SELECT *
                             FROM   Event_Logs
                             WHERE #{filter}
                             /* Time-value with ' UTC' is not accepted for DATETIME(xx, '+ 5 seconds') */
                             AND   (Retry_Count = 0 OR  DATETIME(REPLACE(Last_Error_Time, ' UTC', ''), '+'||CAST(#{MovexCdc::Application.config.error_retry_start_delay}*Retry_Count*Retry_Count AS VARCHAR)||' seconds') < DATETIME('now'))
                             LIMIT  #{fetch_limit}", params)
      end
    else
      []
    end
  end

  # Process given event_logs within one Kafka transaction
  # Method is called within ActiveRecord Transaction
  def process_kafka_transaction(event_logs, concurrent_transaction_error_retry: 0)
    # Kafka transactions requires that deliver_messages is called within transaction. Otherwhise commit_transaction and abort_transaction will end up in Kafka::InvalidTxnStateError
    @kafka_producer.begin_transaction
    event_logs_slices = event_logs.each_slice(@max_message_bulk_count).to_a   # Produce smaller arrays for kafka processing
    Rails.logger.debug "Splitted #{event_logs.count} records in event_logs into #{event_logs_slices.count} slices"
    event_logs_slices.each do |event_logs_slice|
      Rails.logger.debug "Process event_logs_slice with #{event_logs_slice.count} records"
      begin
        event_logs_slice.each do |event_log|
          @max_event_logs_id = event_log['id'] if event_log['id'] > @max_event_logs_id  # remember greatest processed ID to ensure lower IDs from pending transactions are also processed neartime
          table = table_cache(event_log['table_id'])
          kafka_message = prepare_message_from_event_log(event_log, table)
          topic = table.topic_to_use
          @statistic_counter.increment_uncomitted_success(table.id, event_log['operation'])    # unsure up to now if really successful
          begin
            @kafka_producer.produce(kafka_message, topic: topic, key: event_log['msg_key']) # Store messages in local collection, Kafka::BufferOverflow exception is handled by divide&conquer
          rescue Kafka::BufferOverflow => e
            handle_kafka_buffer_overflow(e, kafka_message, topic, table)
            raise                                                               # Ensure transaction is rolled back an retried
          end
        end
        @kafka_producer.deliver_messages                                        # bulk transfer of messages from collection to kafka
      rescue Kafka::MessageSizeTooLarge => e
        Rails.logger.warn "#{e.class} #{e.message}: max_message_size = #{@max_message_size}, max_buffer_size = #{@max_message_bulk_count}, max_buffer_bytesize = #{@max_buffer_bytesize}"
        fix_message_size_too_large(kafka, event_logs_slice)
        raise                                                                   # Ensure transaction is rolled back an retried
      rescue Exception => e
        msg = "TransferThread.process #{@worker_id}: within transaction with transactional_id = #{@transactional_id}. Aborting transaction now.\n"
        msg << event_logs_debug_info(event_logs_slice)
        ExceptionHelper.log_exception(e, 'TransferThread.process_kafka_transaction', additional_msg: msg)
        raise
      end
    end
    @kafka_producer.commit_transaction
    @statistic_counter.commit_uncommitted_success_increments
    @messages_processed_successful += event_logs.count
  rescue Exception => e
    @statistic_counter.rollback_uncommitted_success_increments
    @kafka_producer.abort_transaction
    @kafka_producer.clear_buffer                                                 # remove all pending (not processed by kafka) messages from producer buffer

    max_concurrent_transaction_error_retries = 1
    # Kafka::ConcurrentTransactionError is raised in TransactionManager.add_partitions_to_transaction some times, possibly if next transaction started too fast
    if e.class == Kafka::ConcurrentTransactionError
      if concurrent_transaction_error_retry < max_concurrent_transaction_error_retries
        sleep @concurrent_tx_retry_delay_ms/1000.0
        # Give it a second try, no event is processed yet because error is raised while adding partitions to transaction
        Rails.logger.debug "Kafka::ConcurrentTransactionError catched. Trying 'process_kafka_transaction' again."
        process_kafka_transaction(event_logs, concurrent_transaction_error_retry: concurrent_transaction_error_retry + 1)
      else
        Rails.logger.error('TransferThread.process_kafka_transaction'){"Aborting Kafka transaction at second try after sleeping #{@concurrent_tx_retry_delay_ms} ms due to #{e.class}:#{e.message}"}
        if @concurrent_tx_retry_delay_ms < 1000                                 # Max. 1 second for delay
          Rails.logger.warn('TransferThread.process_kafka_transaction'){"Increasing @concurrent_tx_retry_delay_ms to #{@concurrent_tx_retry_delay_ms} ms to prevent from Kafka::ConcurrentTransactionError next time"}
          @concurrent_tx_retry_delay_ms = @concurrent_tx_retry_delay_ms * 10    # Increase ot sufficient value
        end
        raise
      end
    else
      Rails.logger.error('TransferThread.process_kafka_transaction'){"Aborting Kafka transaction due to #{e.class}:#{e.message}"}
      raise
    end
  end

  # get min id for event_logs with msg_key where this worker instance is responsible for
  def get_min_key_id(msg_key_filter_condition, params, partition_name)
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      Database.select_one("SELECT MIN(ID) FROM Event_Logs#{" PARTITION (#{partition_name})" if partition_name} WHERE #{msg_key_filter_condition}", params)
    when 'SQLITE' then
      Database.select_one("SELECT MIN(ID) FROM Event_Logs WHERE #{msg_key_filter_condition}", params)
    end
  end

  def delete_event_logs_batch(event_logs)
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      begin
        sql = "DELETE /*+ ROWID */ FROM Event_Logs WHERE RowID IN (SELECT /*+ CARDINALITY(d, 1) \"Hint should lead to nested loop and rowid access on Event_Logs \"*/ Column_Value FROM TABLE(?) d)"
        jdbc_conn = ActiveRecord::Base.connection.raw_connection
        cursor = jdbc_conn.prepareStatement sql
        ActiveSupport::Notifications.instrumenter.instrument('sql.active_record', sql: sql, name: "TransferThread DELETE with #{event_logs.count} records") do
          array = jdbc_conn.createARRAY("#{MovexCdc::Application.config.db_user}.ROWID_TABLE".to_java, event_logs.map{|e| e['row_id']}.to_java);
          cursor.setArray(1, array)
          result = cursor.executeUpdate
          if result != event_logs.length
            raise "Error in TransferThread.delete_event_logs_batch: Only #{result} records hit by DELETE instead of #{event_logs.length}."
          end
        end
      rescue Exception => e
        ExceptionHelper.log_exception(e, 'TransferThread.delete_event_logs_batch', additional_msg: "Erroneous SQL:\n#{sql}")
        raise
      ensure
        cursor.close if defined? cursor && !cursor.nil?
      end
    when 'SQLITE' then
      event_logs.each do |e|
        rows = Database.execute "DELETE FROM Event_Logs WHERE ID = :id", id: e['id']  # No known way for SQLite to execute in array binding
        raise "Error in TransferThread.delete_event_logs_batch: Only #{rows} records hit by DELETE instead of exactly one" if rows != 1
      end
    end
  end

  # Process isolated single erroneous event
  def process_single_erroneous_event_log(event_log, exception)
    @messages_processed_with_error +=  1

    case MovexCdc::Application.config.db_type                                # How to access Event_Logs record for several databases
    when 'ORACLE' then filter_sql = "RowID = :row_id"; filter_value = { row_id: event_log['row_id'] }
    when 'SQLITE' then filter_sql = "ID = :id";        filter_value = { id:    event_log['id'] }
    end

    if event_log['retry_count'] < MovexCdc::Application.config.error_max_retries
      # increase number of retries and last error time
      @statistic_counter.increment(event_log['table_id'], event_log['operation'], :events_delayed_errors)
      Rails.logger.debug("TransferThread.process_single_erroneous_event_log"){"Increase Retry_Count for Event_Logs.ID = #{event_log['id']}"}
      Database.execute "UPDATE Event_Logs SET Retry_Count = Retry_Count + 1, Last_Error_Time = #{Database.systimestamp} WHERE #{filter_sql}", filter_value
    else
      # move event_log to list of erroneous and delete from queue
      @statistic_counter.increment(event_log['table_id'], event_log['operation'], :events_final_errors)
      Rails.logger.debug("TransferThread.process_single_erroneous_event_log"){"Move to final error for Event_Logs.ID = #{event_log['id']}"}
      Database.execute "INSERT INTO Event_Log_Final_Errors(ID, Table_ID, Operation, DBUser, Payload, Msg_Key, Created_At, Error_Time, Error_Msg, Transaction_ID)
                       SELECT ID, Table_ID, Operation, DBUser, Payload, Msg_Key, Created_At, #{Database.systimestamp}, :error_msg, Transaction_ID
                       FROM   Event_Logs
                       WHERE #{filter_sql}", { error_msg: "#{exception.class}:#{exception.message}. #{ExceptionHelper.explain_exception(exception)}"}.merge(filter_value)
      Database.execute "DELETE FROM Event_Logs WHERE #{filter_sql}", filter_value
    end
  end

  def prepare_message_from_event_log(event_log, table)
    msg = "{
\"id\": #{event_log['id']},
\"schema\": \"#{table.schema.name}\",
\"tablename\": \"#{table.name}\",
\"operation\": \"#{KeyHelper.long_operation_from_short(event_log['operation'])}\",
\"dbuser\": \"#{event_log['dbuser']}\",
\"timestamp\": \"#{timestamp_as_iso_string(event_log['created_at'])}\",
\"transaction_id\": #{event_log['transaction_id'].nil? ? "null" : "\"#{event_log['transaction_id']}\"" },
#{event_log['payload']}
}"
    @max_message_size = msg.bytesize if msg.bytesize > @max_message_size
    JSON.parse(msg) if Rails.env.test?                                          # Check valid JSON structure for all test modes
    msg
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

  def sleep_and_watch(sleeptime)
    Rails.logger.debug "TransferThread.sleep_and_watch: Sleeping #{sleeptime} seconds" if sleeptime > 0
    1.upto(sleeptime) do
      sleep(1)
      if @thread_mutex.synchronize { @stop_requested }                          # Cancel sleep if stop requested
        return                                                                  # return immediate
      end
    end
  end

  # fix Exception Kafka::MessageSizeTooLarge
  # enlarge Topic property "max.message.bytes" to needed value
  def fix_message_size_too_large(kafka, event_logs)

    # get max. message value sizes per topic
    topic_info = {}
    event_logs.each do |event_log|
      table = table_cache(event_log['table_id'])
      kafka_message = prepare_message_from_event_log(event_log, table)
      topic = table.topic_to_use

      topic_info[topic] = { max_message_value_size: 0} unless topic_info.has_key?(topic)
      topic_info[topic][:max_message_value_size] = kafka_message.bytesize if kafka_message.bytesize > topic_info[topic][:max_message_value_size]
    end

    topic_info.each do |key, value|
      Rails.logger.warn "TransferThread.fix_message_size_too_large: Messages for topic '#{key}' have max. size per message of #{value[:max_message_value_size]} bytes for transfer"
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
    rescue Exception => e
      Rails.logger.error "TransferThread.fix_message_size_too_large: #{e.class}: #{e.message} while getting or setting topic property max.message.bytes"
    end
  end

  def require_option(options, option_name)
    raise "Option ':#{option_name}' required!" unless options[option_name]
    options[option_name]
  end

  def log_exception_with_worker_state(exception, context, message:)
    ExceptionHelper.log_exception(exception, context, additional_msg: "#{message}
#{JSON.pretty_generate(thread_state(without_stacktrace: true))}
#{JSON.pretty_generate(ExceptionHelper.memory_info_hash)}")
  end

  def table_cache(table_id)
    check_record_cache_for_aging
    cache_key = "Table #{table_id}"
    unless @record_cache.has_key? cache_key
      @record_cache[cache_key] = Table.joins(:schema).find(table_id)
    end
    @record_cache[cache_key]
  end

  RECORD_CACHE_REFRESH_CYCLE = 60                                               # Number of seconds between cache refeshes
  def check_record_cache_for_aging
    unless @record_cache.has_key? :first_access
      @record_cache[:first_access] = Time.now
    end
    if @record_cache[:first_access] + RECORD_CACHE_REFRESH_CYCLE < Time.now
      Rails.logger.debug "TransferThread.check_record_cache_for_aging: Reset record cache after #{RECORD_CACHE_REFRESH_CYCLE} seconds"
      @record_cache = {}                                                        # reset record cache after 1 minute to reread possibly changed topic names
    end
  end

  # get maxium used ID, preferred from sequence
  def get_max_event_logs_id_from_sequence
    max_event_logs_id_from_sequence = case MovexCdc::Application.config.db_type
                                      when 'ORACLE' then Database.select_one "SELECT Last_Number FROM User_Sequences WHERE Sequence_Name = 'EVENT_LOGS_SEQ'"
                                      when 'SQLITE' then Database.select_one "SELECT seq FROM SQLITE_SEQUENCE WHERE Name = 'event_logs'"
                                      end
    max_event_logs_id_from_sequence = 0 if max_event_logs_id_from_sequence.nil? # No result found by not already initialized sequence
    max_event_logs_id_from_sequence
  end

  # Set the value per partition
  def increase_max_sorted_id_distance(partition_name, factor)
    key = check_max_sorted_id_distance_for_init partition_name
    @max_sorted_id_distances[key] = ((@max_sorted_id_distances[key] + 1) * factor).to_i
  end

  def decrease_max_sorted_id_distance(partition_name, factor)
    key = check_max_sorted_id_distance_for_init partition_name
    @max_sorted_id_distances[key] = (@max_sorted_id_distances[key] / factor).to_i
  end

  def get_max_sorted_id_distance(partition_name)
    key = check_max_sorted_id_distance_for_init partition_name
    @max_sorted_id_distances[key]
  end

  def check_max_sorted_id_distance_for_init(external_key)
    key = external_key ? external_key : 'default'
    @max_sorted_id_distances[key] = @max_transaction_size * MovexCdc::Application.config.initial_worker_threads unless @max_sorted_id_distances.has_key? key # Initialization
    key
  end

  def housekeep_max_sorted_id_distance(partition_names)
    @max_sorted_id_distances.each do |key, value|
      if key != 'default' && !partition_names.include?(key)
        @max_sorted_id_distances.delete(key)
        Rails.logger.debug("TransferThread.housekeep_max_sorted_id_distance: Removed entry for partition #{key}")
      end
    end
  end

  # get summary text message for event_logs array
  def event_logs_debug_info(event_logs)
    topics = {}
    event_logs.each do |event_log|
      table = table_cache(event_log['table_id'])
      topic = table.topic_to_use
      topics[topic]                     = { events_with_key: 0, events_without_key: 0, tables: {} } unless topics.has_key?(topic)
      topics[topic][:tables][table.id]  = { schema_name: table.schema.name, table_name: table.name, events_with_key: 0, events_without_key: 0 } unless topics[topic][:tables].has_key?(table.id)
      if event_log['msg_key'].nil?
        topics[topic][:events_without_key] += 1
        topics[topic][:tables][table.id][:events_without_key] += 1
      else
        topics[topic][:events_with_key] += 1
        topics[topic][:tables][table.id][:events_with_key] += 1
      end
    end

    topics = topics.sort.to_h

    msg = "Number of records to deliver to kafka = #{event_logs.count}\n"
    topics.each do |topic_name, topic_values|
      msg << "#{topic_values[:events_with_key] + topic_values[:events_without_key]} records for topic '#{topic_name}' (#{topic_values[:events_with_key]} records with key, #{topic_values[:events_without_key]} records without key)\n"
      topic_values[:tables] = topic_values[:tables].sort{|a,b| "#{a[:schema_name]}.#{a[:table_name]}" <=> "#{b[:schema_name]}.#{b[:table_name]}"}.to_h
      topic_values[:tables].each do |table_id, table_values|
        msg << "#{table_values[:events_with_key] + table_values[:events_without_key]} records in topic '#{topic_name}' for table #{table_values[:schema_name]}.#{table_values[:table_name]} (#{table_values[:events_with_key]} records with key, #{table_values[:events_without_key]} records without key)\n"
      end
    end
    msg
  end

  # Reduce the number of messages in bulk if exception occurs
  def handle_kafka_buffer_overflow(exception, kafka_message, topic, table)
    Rails.logger.warn "#{exception.class} #{exception.message}: max_buffer_size = #{@max_message_bulk_count}, max_buffer_bytesize = #{@max_buffer_bytesize}, current message value size = #{kafka_message.bytesize}, topic = #{topic}, schema = #{table.schema.name}, table = #{table.name}"
    if kafka_message.bytesize > @max_buffer_bytesize / 3
      Rails.logger.error('TransferThread.handle_kafka_buffer_overflow'){"Single message size exceeds 1/3 of the Kafka buffer size! No automatic action called! Possibly increase KAFKA_TOTAL_BUFFER_SIZE_MB to fix this issue."}
    else
      reduce_step = @max_message_bulk_count / 10                  # Reduce by 10%
      if @max_message_bulk_count > reduce_step + 1
        @max_message_bulk_count -= reduce_step
        MovexCdc::Application.config.kafka_max_bulk_count = @max_message_bulk_count  # Ensure reduced value is valid also for new TransferThreads
        Rails.logger.warn "Reduce max_message_bulk_count by #{reduce_step} to #{@max_message_bulk_count} to prevent this situation"
      end
    end
  end

  # how long should be waited after processing of whole DB transaction
  def calc_idle_sleep_time(processed_events_count:, current_idle_sleep_time:)
    current_idle_sleep_time = current_idle_sleep_time * 100 if Rails.env.test?  # restore comparable sleep time for following calculation

    new_sleep_time = case
                     when processed_events_count > @max_transaction_size/5 then 0 # Ensure also small max transactions do immediately proceed
                     when processed_events_count < 10 && current_idle_sleep_time < 60 then current_idle_sleep_time + 10 # increase sleep time if < 10 records are processed in last loop
                     when processed_events_count < 10 then 60                   # sleep_time for < 10 is already 60 then stay at this level
                     when processed_events_count < 100 then 5
                     when processed_events_count < 1000 then 2
                     when processed_events_count >= 1000 then 0
                     else 60                                                    # this line should never be reached
                     end
    new_sleep_time = new_sleep_time/100.0 if Rails.env.test?                    # ensure test processes are fast enough, reduce sleep time
    new_sleep_time
  end

end



