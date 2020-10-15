# singleton, cumulates statistics, flush to database is triggered by SystemValidationJob
class StatisticCounterConcentrator
  @@instance = nil
  def self.get_instance
    @@instance = StatisticCounterConcentrator.new if @@instance.nil?
    @@instance
  end

  # called from different threads
  # counter_type = :events_success | :events_failure
  def cumulate(values_hash)
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
    Rails.logger.debug "StatisticCounterConcentrator.flush_to_db: Writing statistics record into table"
    @values_mutex.synchronize do
      ActiveRecord::Base.transaction do
        @values.each do |table_id, operations|
          operations.each do |operation, counter_types|
            counter_types.each do |counter_type, counter|

              events_success          = counter_type == :events_success           ? counter : 0
              events_delayed_errors   = counter_type == :events_delayed_errors    ? counter : 0
              events_final_errors     = counter_type == :events_final_errors      ? counter : 0
              events_d_and_c_retries  = counter_type == :events_d_and_c_retries   ? counter : 0
              events_delayed_retries  = counter_type == :events_delayed_retries   ? counter : 0
              Statistic.write_record(table_id:                  table_id,
                                     operation:                 operation,
                                     events_success:            events_success,
                                     events_delayed_errors:     events_delayed_errors,
                                     events_final_errors:       events_final_errors,
                                     events_d_and_c_retries:    events_d_and_c_retries,
                                     events_delayed_retries:    events_delayed_retries
              )
              table   = table_cache(table_id)
              schema  = schema_cache(table.schema_id)
              # allow transferring log output to time series database
              Rails.logger.info "Statistics: Schema=#{schema.name}, Table=#{table.name}, Operation=#{KeyHelper.operation_from_short_op(operation)}, " +
                                    "Events_Success=#{events_success}, Events_Delayed_Errors=#{events_delayed_errors}, Events_Final_Errors=#{events_final_errors}, " +
                                    "Events_D_and_C_Retries=#{events_d_and_c_retries}, Events_Delayed_Retries=#{events_delayed_retries}"
            end
          end
        end
      end
      @values = {}                                                              # reset cached statistics
    end
  end

  private
  def initialize
    @values = {}
    @values_mutex = Mutex.new                                                   # Ensure synchronized operations on @values
    @record_cache = {}                                                          # cache Tables and Schemas for ever
  end

  def schema_cache(schema_id)
    key = "Schema #{schema_id}"
    unless @record_cache.has_key? key
      @record_cache[key] = Schema.find schema_id
    end
    @record_cache[key]
  end

  def table_cache(schema_id)
    key = "Table #{schema_id}"
    unless @record_cache.has_key? key
      @record_cache[key] = Table.find schema_id
    end
    @record_cache[key]
  end


end