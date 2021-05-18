# singleton, cumulates statistics, flush to database is triggered by SystemValidationJob
class StatisticCounterConcentrator
  @@instance = nil
  def self.get_instance
    @@instance = StatisticCounterConcentrator.new if @@instance.nil?
    @@instance
  end

  # Necessary only for test to ensure dealing with fresh instance
  def self.remove_instance
    @@instance = nil
  end

  # called from different threads
  # counter_type = :events_success | :events_failure
  def cumulate(values_hash)
    ExceptionHelper.warn_with_backtrace "StatisticCounterConcentrator.cumulate: Mutex @values_mutex is locked by another thread! Waiting until Mutex is freed." if @values_mutex.locked?
    @values_mutex.synchronize do
      values_hash.each do |table_id, operations|
        operations.each do |operation, counter_types|
          counter_types.each do |counter_type, counter|
            @values[table_id]                           = {} unless @values.has_key? table_id
            @values[table_id][operation]                = {} unless @values[table_id].has_key? operation
            @values[table_id][operation][counter_type]  = 0  unless @values[table_id][operation].has_key? counter_type
            @values[table_id][operation][counter_type] += counter
          end
        end
      end
    end
  end

  def flush_to_db
    cloned_values = nil
    ExceptionHelper.warn_with_backtrace "StatisticCounterConcentrator.flush_to_db: Mutex @values_mutex is locked by another thread! Waiting until Mutex is freed." if @values_mutex.locked?
    @values_mutex.synchronize do
      # synchronize shortly, clone (not really) the value and than let concurring threads cumumlate to new one
      # this allows to process the cloned values outside Mutex
      # Test only: because test uses only one DB connection for all threads and synchronizes AR activities it is essential to do all ActiveRecord activities outside additional Mutex synchronize
      cloned_values = @values
      @values = {}                                                              # reset cached statistics
    end

    ActiveRecord::Base.transaction do
      cloned_values.each do |table_id, operations|
        operations.each do |operation, counter_types|
          Statistic.write_record(table_id:                  table_id,
                                 operation:                 operation,
                                 events_success:            counter_types[:events_success],
                                 events_delayed_errors:     counter_types[:events_delayed_errors],
                                 events_final_errors:       counter_types[:events_final_errors],
                                 events_d_and_c_retries:    counter_types[:events_d_and_c_retries],
                                 events_delayed_retries:    counter_types[:events_delayed_retries]
          )
          Rails.logger.debug "Counter_Types: #{counter_types}"

          table = table_cache(table_id)

          # allow transferring log output to time series database
          Rails.logger.info "Statistics: Schema=#{table.schema.name}, Table=#{table.name}, Operation=#{KeyHelper.operation_from_short_op(operation)}, " +
              "Events_Success=#{counter_types[:events_success]}, Events_Delayed_Errors=#{counter_types[:events_delayed_errors]}, Events_Final_Errors=#{counter_types[:events_final_errors]}, " +
              "Events_D_and_C_Retries=#{counter_types[:events_d_and_c_retries]}, Events_Delayed_Retries=#{counter_types[:events_delayed_retries]}"
        end
      end
    end
  end

  private
  def initialize
    @values = {}
    @values_mutex = Mutex.new                                                   # Ensure synchronized operations on @values
    @record_cache = {}                                                          # cache Tables for ever
  end

  def table_cache(table_id)
    cache_key = "Table #{table_id}"
    unless @record_cache.has_key? cache_key
      @record_cache[cache_key] = Table.find table_id
    end
    @record_cache[cache_key]
  end


end