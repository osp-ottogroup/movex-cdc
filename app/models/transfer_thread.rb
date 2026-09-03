require 'kafka_mock'

# preload classes to prevent from 'RuntimeError: Circular dependency detected while autoloading constant' if multiple threads start working simultaneously
require 'database'
# require 'table'
require 'exception_helper'
require 'sorted_id_window'

class TransferThread
  attr_reader :worker_id

  MAX_READ_ITERATIONS = 1000                                                    # max. number of loops spent for one call of read_event_logs_steps

  # Shared budget of loop iterations for one call of read_event_logs_steps.
  # Protects against an infinite loop if the adaptive ID window never converges.
  class LoopGuard
    # @param max_iterations [Integer] number of iterations allowed before processing is cancelled
    def initialize(max_iterations:)
      @max_iterations = max_iterations
      @iterations     = 0
    end

    # Count one iteration of a loop sharing this budget
    # @yieldreturn [String] diagnostic context, evaluated only if the budget is exhausted
    # @return [void]
    # @raise [RuntimeError] if the budget is exhausted
    def tick!
      @iterations += 1
      return if @iterations <= @max_iterations
      msg = "TransferThread::LoopGuard: risk of infinite loop after #{@iterations} iterations. Cancelled now! #{yield}"
      Rails.logger.error('TransferThread::LoopGuard.tick!') { msg }
      raise msg
    end
  end

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
    # Maximum distance between first and greatest ID to ensure that number of read events is less than maximum number of messages to read at once
    # this value is dynamically adjusted at runtime so that the number of read records is as high as possible but below @max_transaction_size
    @sorted_id_windows              = {}                                        # SortedIdWindow per partition name (nil key for non-partitioned tables)
    @start_time                     = Time.now
    @last_active_time               = nil                                       # timestamp of last transfer to kafka
    @messages_processed_successful  = 0                                         # Number of successful message processings
    @messages_processed_with_error  = 0                                         # Number of messages processing trials ending with error
    @max_message_size               = 0                                         # Max. size of single message in bytes
    @db_session_info                = nil                                       # Session ID etc., set after successful connection
    @thread                         = nil                                       # Reference to thread, set in new thread in method process
    @stop_requested                 = false
    @thread_mutex                   = Mutex.new                                 # Ensure access on instance variables from two threads
    @max_event_logs_id              = 0                                         # maximum processed id over all Event_Logs-records of thread, maintained in process_kafka_transaction
    @max_key_event_logs_id          = get_max_event_logs_id_from_sequence       # maximum processed id over all Event_Logs-records of thread with key != NULL, initialized with max value, maintained in read_keyed_events
    # Kafka transactional ID, must be unique per thread / Kafka connection
    @statistic_counter              = StatisticCounter.new
    @record_cache                   = {}                                        # cache subsequent access on Tables and Schemas, each Thread uses it's own cache
    @cached_max_event_logs_seq_id   = @max_key_event_logs_id                    # last known max value from sequence, refreshed by get_max_event_logs_id_from_sequence if required
    @kafka_producer                 = nil                                       # initialized later
    @last_read_events               = 0                                         # number of event_log records read at last read rom event_logs
    @last_scanned_partitions        = 0                                         # number of partitions scanned at last read rom event_logs
    @concurrent_tx_retry_delay_ms   = 1                                         # Amount of delay before retry at org.apache.kafka.common.errors.ConcurrentTransactionsException, increased if not sufficient
    @kafka_connected                = false                                     # flag to ensure that kafka connection is established
  end

  # Do processing in a separate Thread
  def process
    # process Event_Logs for  ID mod worker_count = worker_ID for update skip locked
    Rails.logger.info('TransferThread.process'){"New worker thread created with ID=#{@worker_id}, Thread-ID=#{Thread.current.object_id}"}
    Database.set_application_info("worker #{@worker_id}/process")
    @db_session_info = Database.db_session_info                                          # Session ID etc., get information from within separate thread
    Database.set_current_session_network_timeout(timeout_seconds: MovexCdc::Application.config.db_query_timeout * 2) # ensure hanging sessions are cancelled sometimes
    @thread = Thread.current

    @kafka_producer = KafkaBase.create.create_producer(worker_id: @worker_id)
    Rails.logger.debug('TransferThread.process'){"Kafka producer created with transactional_id = #{@kafka_producer&.current_transactional_id}, marking @kafka_connected = true "}
    @kafka_connected = true                                                     # flag to ensure that kafka connection is established, otherwise exception is raised by create_producer

    # Loop for ever, check cancel criteria in ThreadHandling
    idle_sleep_time = 0
    while !@thread_mutex.synchronize { @stop_requested }
      ActiveRecord::Base.transaction do                                         # commit delete on database only if all messages are processed by kafka, rollback at exception
        event_logs = read_event_logs_batch                                      # read bulk collection of messages from Event_Logs
        @last_read_events = event_logs.count                                    # remember for health check
        if event_logs.count > 0
          @last_active_time = Time.now
          process_event_logs_divide_and_conquer(event_logs)
          @statistic_counter.flush                                              # Write cumulated statistics to singleton memory only if processing happened
        end
        idle_sleep_time = calc_idle_sleep_time(processed_events_count: event_logs.count, current_idle_sleep_time: idle_sleep_time)
      end                                                                       # ActiveRecord::Base.transaction do
      sleep_and_watch(idle_sleep_time * SLEEP_TIME_SCALE)                       # sleep some time outside transaction if no records are to be processed
    end
  rescue Exception => e
    log_exception_with_worker_state(e, 'TransferThread.process',  message: "Worker #{@worker_id}: Terminating thread due to exception")
  ensure
    begin
      @kafka_producer&.shutdown                                                 # free kafka connections before terminating Thread
    rescue Exception => e
      ExceptionHelper.log_exception(e, 'TransferThread.process', additional_msg: "Worker-ID = #{@worker_id}: ensure (Kafka-disconnect)") # Ensure that following actions are processed in any case
    end
    begin
      @statistic_counter.flush                                                  # Write cumulated statistics to singleton memory
      Rails.logger.info('TransferThread.process') { "Worker #{@worker_id}: stopped" }
      Rails.logger.info('TransferThread.process') { JSON.pretty_generate(thread_state(without_stacktrace: true)) }
      ThreadHandling.get_instance.remove_from_pool(self)                 # unregister from threadpool
      Database.close_db_connection                                              # Physically disconnect the DB connection of this thread, so that next request in this thread will re-open the connection again
    rescue Exception => e
      ExceptionHelper.log_exception(e, 'TransferThread.process', additional_msg: "Worker-ID = #{@worker_id}: remaining ensure ") #
      raise                                                                     # this raise may not be caught because it is the last operation of this thread
    end
  end # process

  # Request the current thread to stop processing at next possible occasion
  # This method is called from main thread or job that started the worker thread
  # @return [void]
  def stop_thread                                                               # called from main thread / job
    Rails.logger.info('TransferThread.stop_thread') { "Worker #{@worker_id}: stop request forced" }
    @thread_mutex.synchronize { @stop_requested = true }
  end

  # get Hash with current state info for thread, used e.g. for health check
  def thread_state(options = {})
    retval = {
      cached_max_event_logs_seq_id:   @cached_max_event_logs_seq_id,
      db_session_info:                @db_session_info,
      kafka_connected:                @kafka_connected,
      kafka_producer_metrics:         @kafka_producer&.metrics,
      last_active_time:               @last_active_time,
      last_read_events:               @last_read_events,
      last_scanned_partitions:        @last_scanned_partitions,
      max_event_logs_id:              @max_event_logs_id,
      max_key_event_logs_id:          @max_key_event_logs_id,
      max_message_size:               @max_message_size,
      max_sorted_id_distances:        @sorted_id_windows.map { |key, value| { partition_name: key, max_sorted_id_distance: value.distance } },
      message_processing_errors:      @messages_processed_with_error,
      start_time:                     @start_time,
      successful_messages_processed:  @messages_processed_successful,
      thread_id:                      @thread&.object_id,
      transactional_id:               @kafka_producer&.current_transactional_id,
      worker_id:                      @worker_id,
      warning:                        ''                                        # empty warning means healthy
    }
    retval[:warning] << "DB-connection not established, "    unless @db_session_info
    retval[:warning] << "Kafka-connection not established, " unless @kafka_connected
    retval[:warning] << "Thread not alive, "                 unless @thread&.alive?
    retval[:stacktrace] = @thread&.backtrace unless options[:without_stacktrace]
    retval
  end

  private


  # Process the event_logs array within the AR transaction
  #
  # Events are deleted from Event_Logs only after they have been transferred to Kafka successfully.
  # If the Kafka transaction fails, the array is divided into smaller parts which are processed
  # recursively until a single erroneous event is isolated. Every recursion level deletes the events
  # it processed successfully itself, therefore nothing is left to delete on the failing level.
  #
  # @param event_logs [Array] the event_log records to transfer within one Kafka transaction
  # @param recursive_depth [Integer] current depth of the divide and conquer recursion
  # @return [void]
  def process_event_logs_divide_and_conquer(event_logs, recursive_depth = 0)
    return if event_logs.empty?                                                 # No useful processing of empty arrays, should not occur

    if recursive_depth > 0                                                      # this array is a part of an array that failed before
      event_logs.each { |e| @statistic_counter.increment(e['table_id'], e['operation'], :events_d_and_c_retries) }
    end

    begin
      process_kafka_transaction(event_logs)
    rescue Exception => e
      handle_failed_kafka_transaction(event_logs, e, recursive_depth)           # the isolated parts have deleted their events themselves
      return                                                                    # nothing left to delete at this recursion level
    end

    delete_processed_event_logs(event_logs)                                     # only a committed Kafka transaction reaches this point
  end

  # Isolate the erroneous events of a failed Kafka transaction
  #
  # The array is divided into smaller parts that are processed recursively until a single event
  # remains, which is then moved to the retry / final error handling.
  #
  # @param event_logs [Array] the event_log records of the failed Kafka transaction
  # @param exception [Exception] the exception raised by the Kafka transaction
  # @param recursive_depth [Integer] current depth of the divide and conquer recursion
  # @return [void]
  def handle_failed_kafka_transaction(event_logs, exception, recursive_depth)
    Rails.logger.info('TransferThread.handle_failed_kafka_transaction'){"Divide & conquer with current array size = #{event_logs.count}, recursive depth = #{recursive_depth} due to #{exception.class}:#{exception.message}"}
    if @kafka_producer.producer_reset_needed?(exception)
      Rails.logger.error('TransferThread.handle_failed_kafka_transaction'){"Worker #{@worker_id}: FATAL ERROR in Kafka producer due to #{exception.class}:#{exception.message}. The producer is not usable anymore, reset called!"}
      @kafka_producer.reset_kafka_producer                                      # After transaction error in Kafka the current producer ends up in InvalidTxnStateError if trying to continue with begin_transaction
    end

    if event_logs.count == 1                                                    # single erroneous event isolated now
      process_single_erroneous_event_log(event_logs[0], exception)
    else                                                                        # divide remaining event_logs in smaller parts
      slice_size = event_logs.count / 10                                        # divide the array size by 10 each time an error occurs
      slice_size = 1 if slice_size < 1                                          # ensure minimum size of single array
      event_logs.each_slice(slice_size) do |slice|
        process_event_logs_divide_and_conquer(slice, recursive_depth + 1)       # Process recursively single parts of previous array
      end
    end
  end

  # Delete the events that have been transferred to Kafka successfully
  # @param event_logs [Array] the event_log records of the committed Kafka transaction
  # @return [void]
  # @raise Exception if the delete failed, which rolls back the surrounding AR transaction
  def delete_processed_event_logs(event_logs)
    delete_event_logs_batch(event_logs)
  rescue Exception => e
    ExceptionHelper.log_exception(e, 'TransferThread.delete_processed_event_logs', additional_msg: "delete_event_logs_batch failed. This should never happen and leads to multiple processing of events to Kafka.\n#{event_logs_debug_info(event_logs)}")
    raise
  end

  def read_event_logs_batch
    event_logs = []
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      if MovexCdc::Application.partitioning?
        # Iterate over partitions starting with oldest up to @max_transaction_size records
        Rails.logger.debug('TransferThread.read_event_logs_batch'){"Start iterating over partitions"}
        partitions = Database.select_all("SELECT Partition_Name, High_Value
                                          FROM   User_Tab_Partitions
                                          WHERE  Table_Name = 'EVENT_LOGS'
                                         ").sort_by{|x| x['high_value']}
        Rails.logger.debug('TranferThread.read_event_logs_batch'){"Found #{partitions.count} partitions to scan"}
        @last_scanned_partitions = 0
        partitions.each_index do |i|
          remaining_records = @max_transaction_size - event_logs.count          # available space for more result records
          if remaining_records > 0 # Skip next partitions if already read enough records
            event_logs.concat(read_event_logs_steps(max_records_to_read:  remaining_records,
                                                    partition_name:       partitions[i]['partition_name']
                              )
            )
            @last_scanned_partitions += 1                                       # remember for health check
          end
        end
        housekeep_sorted_id_windows(partitions.map {|p| p['partition_name']})
      else                                                                      # non-partitioned Oracle table
        event_logs.concat(read_event_logs_steps(max_records_to_read: @max_transaction_size))
      end
    when 'SQLITE' then
      event_logs.concat(read_event_logs_steps(max_records_to_read: @max_transaction_size))
    else
      raise "Unsupported DB type '#{MovexCdc::Application.config.db_type}'"
    end

    # adjust cached value to reality for next read if not maximum number of records has been read
    # must be done for every DB type, otherwise read_event_logs_steps keeps working with the value from thread start
    @cached_max_event_logs_seq_id = get_max_event_logs_id_from_sequence if event_logs.count < @max_transaction_size
    event_logs.sort_by! {|e| e['id']}                                           # ensure original order of event creation
    event_logs.each do |e|
      @statistic_counter.increment(e['table_id'], e['operation'], :events_delayed_retries) if e['retry_count'] > 0
    end
    event_logs
  end

  # read event_logs with multiple selects
  # Steps for processing are:
  # 1. read records with key value hash related to this worker (modulo). Each worker is responsible to process a number of keys (identified by modulo) to ensure in order processing to Kafka
  # 2. look for records without key value and with smaller ID than largest of last run (older records)
  # 3. look for records without key value and with larger ID than largest of last run (newer records)
  # @param max_records_to_read [Integer] number of records that still fit into the current batch
  # @param partition_name [String, nil] Event_Logs partition to read from, nil for non-partitioned tables
  # @return [Array] the read Event_Logs records
  def read_event_logs_steps(max_records_to_read:, partition_name: nil)
    window = sorted_id_window(partition_name)                                   # adaptive upper limit for the ID range read at once

    # 1. records with a Msg_Key this worker is responsible for, read in guaranteed order by ID
    result = read_keyed_events(max_records_to_read: max_records_to_read, window: window, partition_name: partition_name)

    # 2. look for records without key value and with smaller ID than largest of last run (older records)
    result.concat read_event_logs_single(fetch_limit:     max_records_to_read - result.count,
                                         filter:          "Msg_Key IS NULL AND ID < :max_id",
                                         params:          {max_id: @max_event_logs_id},
                                         partition_name:  partition_name
                  )

    # 3. look for records without key value and with larger ID than largest of last run (newer records)
    # the order does not matter because without a key Kafka uses random partitions
    # fill rest of buffer with all unlocked records not read by the first SQL (ID>=max_id)
    result.concat read_event_logs_single(fetch_limit:     max_records_to_read - result.count,
                                         filter:          "Msg_Key IS NULL AND ID >= :max_id",
                                         params:          {max_id: @max_event_logs_id},
                                         partition_name:  partition_name
                  )

    result
  end

  # SQL condition identifying the events with Msg_Key this worker instance is responsible for processing.
  # Each worker is responsible for a fixed subset of keys (identified by modulo) to ensure in order processing to Kafka.
  # @return [String] SQL condition using the bind variable :worker_id
  def msg_key_filter_condition
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then "Msg_Key IS NOT NULL AND MOD(ORA_HASH(Msg_Key, 1000000), #{MovexCdc::Application.config.initial_worker_threads}) = :worker_id"
    when 'SQLITE' then "Msg_Key IS NOT NULL AND LENGTH(Msg_Key) % #{MovexCdc::Application.config.initial_worker_threads} = :worker_id" # LENGTH as workaround for not existing hash function
    end
  end

  # Step 1: read the events with Msg_Key this worker instance is responsible for
  #
  # Reads are repeated with a moving ID window until the requested number of records is reached
  # or all currently existing IDs are covered. The window is enlarged if a read used only a small
  # part of the allowed number of records.
  #
  # @param max_records_to_read [Integer] number of records that still fit into the current batch
  # @param window [SortedIdWindow] adaptive ID window of the processed partition
  # @param partition_name [String, nil] Event_Logs partition to read from, nil for non-partitioned tables
  # @return [Array] the read Event_Logs records
  def read_keyed_events(max_records_to_read:, window:, partition_name:)
    Rails.logger.debug('TransferThread.read_keyed_events'){"Start processing with @max_key_event_logs_id = #{@max_key_event_logs_id}, max_sorted_id_distance = #{window.distance}, max_records_to_read = #{max_records_to_read}, @cached_max_event_logs_seq_id = #{@cached_max_event_logs_seq_id}"}
    result     = []
    min_id     = 0                                                              # Maximum ID already selected by previous loop
    loop_guard = LoopGuard.new(max_iterations: MAX_READ_ITERATIONS)             # budget shared with the reads within this loop

    loop do                                                                     # loop until all records read or max_records_to_read reached
      loop_guard.tick! { "@max_key_event_logs_id = #{@max_key_event_logs_id}, max_sorted_id_distance = #{window.distance}, max_records_to_read = #{max_records_to_read}, result.count = #{result.count}" }
      key_result, base_id = read_keyed_events_in_sorted_order(window: window, min_id: min_id, partition_name: partition_name, loop_guard: loop_guard)

      key_result.each {|r| @max_key_event_logs_id = r['id'] if r['id'] > @max_key_event_logs_id }  # remember the highest ID for next run
      min_id = @max_key_event_logs_id
      result.concat key_result

      # break loop if max. amount of record is reached. It is sufficient if more than max_records_to_read are read even if select was done with full @max_transaction_size
      if result.count >= max_records_to_read
        Rails.logger.debug('TransferThread.read_keyed_events'){"break the loop of step 1 because number of read records (#{result.count}) > max_records_to_read (#{max_records_to_read})"}
        break
      end

      # break loop if all possible values of ID have been covered by previous SQL
      if base_id + window.distance > @cached_max_event_logs_seq_id
        Rails.logger.debug('TransferThread.read_keyed_events'){"break the loop of step 1 because base_id (#{base_id}) + max_sorted_id_distance#{" of partition #{partition_name}" if partition_name} (#{window.distance}) > @cached_max_event_logs_seq_id (#{@cached_max_event_logs_seq_id})"}
        break
      end

      # Enlarge max_sorted_id_distance up to maximum if less than 1/3 of @max_transaction_size is used, but don't increase distance for possibly empty older partitions
      if window.growth_useful?(read_count: key_result.count)
        Rails.logger.debug('TransferThread.read_keyed_events'){"Check for increasing of max_sorted_id_distance (#{window.distance})#{" for partition #{partition_name}" if partition_name}, @max_key_event_logs_id = #{@max_key_event_logs_id}, @cached_max_event_logs_seq_id = #{@cached_max_event_logs_seq_id}"}
        # if old distance is below max known ID then increase distance
        window.grow(read_count: key_result.count) if @max_key_event_logs_id + window.distance <= @cached_max_event_logs_seq_id
      end
    end
    result
  end

  # Read the events with Msg_Key for the current position of the ID window
  #
  # A read hitting the limit of @max_transaction_size records has to be discarded:
  # in that case it is not guaranteed that there are no existing records with smaller IDs outside the result,
  # which would break the guaranteed order of events sorted by ID.
  # Then either the window is narrowed or the start ID is lowered, and the read is repeated
  # until the limit key_result.count < @max_transaction_size is reached.
  #
  # @param window [SortedIdWindow] adaptive ID window of the processed partition
  # @param min_id [Integer] only records with a greater ID are read
  # @param partition_name [String, nil] Event_Logs partition to read from, nil for non-partitioned tables
  # @param loop_guard [LoopGuard] protection against an infinite loop, shared with the calling loop
  # @return [Array(Array, Integer)] the read records and the start ID the successful read was based on
  def read_keyed_events_in_sorted_order(window:, min_id:, partition_name:, loop_guard:)
    loop do                                                                     # loop until records read at once are < @max_transaction_size to ensure sorted order
      loop_guard.tick! { "@max_key_event_logs_id = #{@max_key_event_logs_id}, max_sorted_id_distance = #{window.distance}, min_id = #{min_id}" }
      base_id = @max_key_event_logs_id                                          # remember the value used for SQL, the caller needs it for its break clause
      # @max_transaction_size instead of max_records_to_read is the limit here to ensure even distances also if events from previous and next partition are combined
      key_result = read_event_logs_single(fetch_limit:      @max_transaction_size,
                                          filter:           "ID > :min_ID AND ID < :max_id AND #{msg_key_filter_condition}",
                                          params:           {min_id: min_id, max_id: base_id + window.distance, worker_id: @worker_id},
                                          partition_name:   partition_name
      )

      # it is ensured that no unread records are remaining with key IS NOT NULL and ID < @max_key_event_logs_id (sorted order ensured)
      return [key_result, base_id] if key_result.count < @max_transaction_size

      # now handle that it has not been guaranteed that outside the read records (key_result) there are existing records with smaller IDs
      # This will break the guaranteed order of events sorted by ID, therefore reduce the amount of read records in next attempt
      # Discard the read result and prepare next loop execution to reach the limit key_result.count < @max_transaction_size and ensure processing of all smaller IDs
      if window.shrinkable?                                                     # Possible to read more than @max_transaction_size records
        # Reduce the window so that the next read stays below @max_transaction_size records but still returns more than 0
        window.shrink_to_fit(lowest_read_id: key_result.map{|r| r['id']}.min, base_id: base_id)
      else                                                                      # There must exist more records in table with id < @max_key_event_logs_id + max_sorted_id_distance than @max_transaction_size
        # Start next run with smaller max. id but ensure to catch at least one record
        @max_key_event_logs_id = get_min_key_id(msg_key_filter_condition, {worker_id: @worker_id}, partition_name) - 1
        Rails.logger.debug('TransferThread.read_keyed_events_in_sorted_order'){"@max_key_event_logs_id decreased to #{@max_key_event_logs_id} because there are still to much records below @max_key_event_logs_id + max_sorted_id_distance (#{window.distance})#{" for partition #{partition_name}" if partition_name}"}
      end
    end
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
  # @param event_logs [Array] array of event_log records to process
  # @param concurrent_transaction_error_retry [Integer] number of retries at org.apache.kafka.common.errors.ConcurrentTransactionsException
  # @return [void]
  # @raise Exception if processing failed, in this case no event_log records are deleted
  def process_kafka_transaction(event_logs, concurrent_transaction_error_retry: 0)
    @kafka_producer.begin_transaction
    Rails.logger.debug('TransferThread.process_kafka_transaction'){"Process event_logs with #{event_logs.count} records"}
    begin
      event_logs.each do |event_log|
        # remember greatest processed ID to ensure lower IDs from pending transactions are also processed neartime.
        # This watermark is advanced while producing, so also for a transaction that is aborted afterwards.
        # No event is lost by that because step 2 and 3 of read_event_logs_steps together cover the whole ID range, only the border between them moves.
        @max_event_logs_id = event_log['id'] if event_log['id'] > @max_event_logs_id
        table = table_cache(event_log['table_id'])
        kafka_message = prepare_message_from_event_log(event_log, table)
        @statistic_counter.increment_uncomitted_success(table.id, event_log['operation'])    # unsure up to now if really successful
        @kafka_producer.produce(message: kafka_message, table: table, key: event_log['msg_key'], headers: create_message_headers(event_log, table))
      end
    rescue Exception => e
      msg = "TransferThread.process #{@worker_id}: within transaction with transactional_id = #{@kafka_producer&.current_transactional_id}. Aborting transaction now.\n"
      msg << event_logs_debug_info(event_logs)
      ExceptionHelper.log_exception(e, 'TransferThread.process_kafka_transaction', additional_msg: msg)
      raise
    end
    @kafka_producer.commit_transaction
    @statistic_counter.commit_uncommitted_success_increments
    @messages_processed_successful += event_logs.count
  rescue Exception => e
    @statistic_counter.rollback_uncommitted_success_increments
    begin
      @kafka_producer.abort_transaction
      # Calling abort_transaction will lead to InvalidTxnStateError if called after commit_transaction returned TimeoutException, aajust max.block.ms and retries for producer to prevent this
      # java.lang.IllegalStateException: Cannot attempt operation `abortTransaction` because the previous call to `commitTransaction` timed out and must be retried
    rescue java.lang.IllegalStateException => e2
      if e.class == org.apache.kafka.common.errors.TimeoutException
        Rails.logger.error('TransferThread.process_kafka_transaction'){"java.lang.IllegalStateException caught at producer.abort_transaction.: #{e2.message}"}
        Rails.logger.error('TransferThread.process_kafka_transaction'){"This is because abort_transaction was called after a TimeoutException possible from commit_transaction."}
        Rails.logger.error('TransferThread.process_kafka_transaction'){"In this case it is not clear if commit_transaction succeeded or not (mostly not). Producer must be recreated in that case."}
      else
        ExceptionHelper.log_exception(e2, 'TransferThread.process_kafka_transaction', additional_msg: "Calling producer.abort_transaction raised #{e.class}:#{e.message}")
      end
    end

    max_concurrent_transaction_error_retries = 1
    # org.apache.kafka.common.errors.ConcurrentTransactionsException is raised in TransactionManager.add_partitions_to_transaction some times, possibly if next transaction started too fast
    if e.class == org.apache.kafka.common.errors.ConcurrentTransactionsException
      if concurrent_transaction_error_retry < max_concurrent_transaction_error_retries
        sleep @concurrent_tx_retry_delay_ms/1000.0
        # Give it a second try, no event is processed yet because error is raised while adding partitions to transaction
        Rails.logger.info('TransferThread.process_kafka_transaction'){"org.apache.kafka.common.errors.ConcurrentTransactionsException caught. Trying 'process_kafka_transaction' again."}
        process_kafka_transaction(event_logs, concurrent_transaction_error_retry: concurrent_transaction_error_retry + 1)
      else
        Rails.logger.error('TransferThread.process_kafka_transaction'){"Aborting Kafka transaction at second try after sleeping #{@concurrent_tx_retry_delay_ms} ms due to #{e.class}:#{e.message}"}
        if @concurrent_tx_retry_delay_ms < 1000                                 # Max. 1 second for delay
          @concurrent_tx_retry_delay_ms = @concurrent_tx_retry_delay_ms * 10    # Increase of sufficient value
          Rails.logger.warn('TransferThread.process_kafka_transaction'){"Increasing @concurrent_tx_retry_delay_ms to #{@concurrent_tx_retry_delay_ms} ms to prevent from org.apache.kafka.common.errors.ConcurrentTransactionsException next time"}
        end
        raise
      end
    else
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
      DatabaseOracle.execute_for_rowid_list(
        stmt: "DELETE /*+ ROWID */ FROM Event_Logs WHERE RowID IN (SELECT /*+ CARDINALITY(d, 1) \"Hint should lead to nested loop and rowid access on Event_Logs \"*/ Column_Value FROM TABLE(?) d)",
        rowid_array: event_logs.map{|e| e['row_id']},
        name: "TransferThread DELETE with #{event_logs.count} records"
      )
    when 'SQLITE' then
      event_logs.each do |e|
        rows = Database.execute "DELETE FROM Event_Logs WHERE ID = :id", binds: { id: e['id']}  # No known way for SQLite to execute in array binding
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
      Database.execute "UPDATE Event_Logs SET Retry_Count = Retry_Count + 1, Last_Error_Time = #{Database.systimestamp_sql} WHERE #{filter_sql}", binds: filter_value
    else
      # move event_log to list of erroneous and delete from queue
      @statistic_counter.increment(event_log['table_id'], event_log['operation'], :events_final_errors)
      Rails.logger.error("TransferThread.process_single_erroneous_event_log"){"Move event to final error for Event_Logs.ID = #{event_log['id']}"}
      Database.execute "INSERT INTO Event_Log_Final_Errors(ID, Table_ID, Operation, DBUser, Payload, Msg_Key, Created_At, Error_Time, Error_Msg, Transaction_ID)
                       SELECT ID, Table_ID, Operation, DBUser, Payload, Msg_Key, Created_At, #{Database.systimestamp_sql}, :error_msg, Transaction_ID
                       FROM   Event_Logs
                       WHERE #{filter_sql}", binds: { error_msg: "#{exception.class}:#{exception.message}. #{ExceptionHelper.explain_exception(exception)}"}.merge(filter_value)
      Database.execute "DELETE FROM Event_Logs WHERE #{filter_sql}", binds: filter_value
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
    if event_log['payload'].nil? or event_log['payload'].empty?
      Rails.logger.warn("TransferThread.prepare_message_from_event_log"){"Payload is empty, event will not be processed! Message content is:\n#{msg}"}
      raise "TransferThread.prepare_message_from_event_log: Payload is empty! Message content is shown in previous warn output"
    end

    @max_message_size = msg.bytesize if msg.bytesize > @max_message_size
    if Rails.env.test?                                          # Check valid JSON structure for all test modes
      begin
        JSON.parse(msg)
      rescue JSON::ParserError => e
        raise "Error #{e.class}:#{e.message} while parsing #{msg}"
      end
    end
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
    case MovexCdc::Application.config.legacy_ts_format
    when nil then                                                               # ISO 8601 format with dot as fraction delimiter and DB timezone with colon
      "#{timestamp_as_time.strftime "%Y-%m-%dT%H:%M:%S.%6N"}#{MovexCdc::Application.config.db_default_timezone}"
    when 'TYPE_1' then                                                          # Fraction delimiter is comma instead of dot and timezone of local machine without colon
      "#{timestamp_as_time.strftime "%Y-%m-%dT%H:%M:%S,%6N%z"}"
    when 'TYPE_2' then                                                          # Fraction delimiter is comma instead of dot
      "#{timestamp_as_time.strftime "%Y-%m-%dT%H:%M:%S,%6N"}#{MovexCdc::Application.config.db_default_timezone}"
    end
  end

  # Sleep the given time, but check once per second if the thread should stop
  # @param sleeptime [Numeric] seconds to sleep, may be fractional
  # @return [void]
  def sleep_and_watch(sleeptime)
    return if sleeptime <= 0                                                    # no action for sleeptime == 0
    Rails.logger.debug('TransferThread.sleep_and_watch'){"Sleeping #{sleeptime} seconds"}
    full_seconds, remainder = sleeptime.divmod(1)                               # fractional sleep times are used in test environment
    full_seconds.to_i.times do
      sleep(1)
      return if @thread_mutex.synchronize { @stop_requested }                   # Cancel sleep if stop requested
    end
    sleep(remainder) if remainder > 0                                           # must not be interrupted for small wait times
  end

  # Get a mandatory option from the options Hash
  # @param options [Hash] the options passed to the worker
  # @param option_name [Symbol] name of the required option
  # @return [Object] the value of the option, may also be false or 0
  def require_option(options, option_name)
    raise "Option ':#{option_name}' required!" unless options.has_key?(option_name)
    options[option_name]
  end

  def log_exception_with_worker_state(exception, context, message:)
    ExceptionHelper.log_exception(exception, context, additional_msg: "#{message}
#{JSON.pretty_generate(thread_state(without_stacktrace: true))}
#{JSON.pretty_generate(ExceptionHelper.memory_info_hash)}")
  end

  # Suppress subsequent DB access for table config
  # @param [Integer] table_id
  # @return [Table] the cached object
  def table_cache(table_id)
    check_record_cache_for_aging
    cache_key = "Table_#{table_id}"
    unless @record_cache.has_key? cache_key
      @record_cache[cache_key] = Table.joins(:schema).find(table_id)
      Rails.logger.debug('TransferThread.table_cache'){"Read table record for table_id = #{table_id}: #{@record_cache[cache_key]}"}
    end
    @record_cache[cache_key]
  end

  RECORD_CACHE_REFRESH_CYCLE = 60                                               # Number of seconds between cache refreshes
  def check_record_cache_for_aging
    unless @record_cache.has_key? :first_access
      @record_cache[:first_access] = Time.now
    end
    if @record_cache[:first_access] + RECORD_CACHE_REFRESH_CYCLE < Time.now
      Rails.logger.debug('TransferThread.check_record_cache_for_aging'){"Reset record cache after #{RECORD_CACHE_REFRESH_CYCLE} seconds"}
      @record_cache = {}                                                        # reset record cache after 1 minute to reread possibly changed topic names
    end
  end

  # get maximum used ID, preferred from sequence
  def get_max_event_logs_id_from_sequence
    max_event_logs_id_from_sequence = case MovexCdc::Application.config.db_type
                                      when 'ORACLE' then Database.select_one "SELECT Last_Number FROM User_Sequences WHERE Sequence_Name = 'EVENT_LOGS_SEQ'"
                                      when 'SQLITE' then Database.select_one "SELECT seq FROM SQLITE_SEQUENCE WHERE Name = 'event_logs'"
                                      end
    max_event_logs_id_from_sequence = 0 if max_event_logs_id_from_sequence.nil? # No result found by not already initialized sequence
    max_event_logs_id_from_sequence
  end

  # Get the adaptive ID window for a partition, create it at first access
  # @param [String, nil] partition_name Name of the Event_Logs partition, nil for non-partitioned tables
  # @return [SortedIdWindow] the window belonging to this partition
  def sorted_id_window(partition_name)
    @sorted_id_windows[partition_name] ||= SortedIdWindow.new(max_transaction_size: @max_transaction_size, partition_name: partition_name)
  end

  # Remove windows for already dropped partitions
  # @param [Array] partition_names List of already existing partitions
  def housekeep_sorted_id_windows(partition_names)
    @sorted_id_windows.keys.each do |key|                                       # keys as snapshot because the Hash is modified within the loop
      if !key.nil? && !partition_names.include?(key)
        @sorted_id_windows.delete(key)
        Rails.logger.debug('TransferThread.housekeep_sorted_id_windows'){"Removed entry for partition '#{key}'"}
      end
    end
  end

  # get summary text message for event_logs array
  # @param [Array] event_logs Array of records from table Event_Logs
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
      topic_values[:tables] = topic_values[:tables].sort_by { |_key,value| "#{value[:schema_name]}.#{value[:table_name]}" }.to_h
      topic_values[:tables].each do |table_id, table_values|
        msg << "#{table_values[:events_with_key] + table_values[:events_without_key]} records in topic '#{topic_name}' for table #{table_values[:schema_name]}.#{table_values[:table_name]} (#{table_values[:events_with_key]} records with key, #{table_values[:events_without_key]} records without key)\n"
      end
    end
    msg
  end

  SLEEP_TIME_SCALE = Rails.env.test? ? 0.01 : 1                                 # ensure test processes are fast enough, applied when the calculated time is really slept

  # how long should be waited after processing of whole DB transaction
  # @param processed_events_count [Integer] number of events processed in the last loop
  # @param current_idle_sleep_time [Numeric] result of the previous call, unscaled seconds
  # @return [Numeric] the new sleep time in unscaled seconds, to be multiplied with SLEEP_TIME_SCALE before sleeping
  def calc_idle_sleep_time(processed_events_count:, current_idle_sleep_time:)
    max_sleep_time = MovexCdc::Application.config.max_worker_thread_sleep_time
    new_sleep_time = case
                     when processed_events_count > @max_transaction_size/5 then 0 # Ensure also small max transactions do immediately proceed
                     when processed_events_count < 10 && current_idle_sleep_time < max_sleep_time then current_idle_sleep_time + 10 # increase sleep time if < 10 records are processed in last loop
                     when processed_events_count < 10 then max_sleep_time       # sleep_time for < 10 is already set then stay at this level
                     when processed_events_count < 100 then 5
                     when processed_events_count < 1000 then 2
                     when processed_events_count >= 1000 then 0
                     else max_sleep_time                                        # this line should never be reached
                     end
    new_sleep_time = max_sleep_time if new_sleep_time > max_sleep_time          # Correct to max. if current + step exceeds maximum
    new_sleep_time
  end

  # Create header hash for an event if requested
  # @param [EventLog] event_log the message to process
  # @param [Table] table cached table record
  # @return [Hash]
  def create_message_headers(event_log, table)
    if table.yn_add_cloudevents_header == 'N'
      {}
    else
      {
        ce_id:              event_log['id'].to_s,
        ce_source:          MovexCdc::Application.config.cloudevents_source,
        ce_specversion:     '1.0',
        ce_type:            "MOVEX-CDC:#{MovexCdc::Application.config.build_version}",
        ce_time:            timestamp_as_iso_string(event_log['created_at']),
        ce_datacontenttype: 'application/json',
        ce_schema:          table.schema.name,
        ce_tablename:       table.name,
        ce_operation:       KeyHelper.long_operation_from_short(event_log['operation'])
      }
    end
  end
end



