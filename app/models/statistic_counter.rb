class StatisticCounter
  # each worker thread should have its own instance

  def initialize
    @values = {}
    @uncommitted_values = {}                                                    # temporary cumulated values, must be commited by commit_uncommited_increments
  end

  def self.supported_counter_types
    [:events_success, :events_delayed_errors, :events_final_errors, :events_d_and_c_retries, :events_delayed_retries]
  end

  # incement events counter no matter if success or error
  def increment(table_id, operation, counter_type, inc_value=1)
    raise "StatisticCounter.increment: Unsupported counter_type '#{counter_type}'" unless StatisticCounter.supported_counter_types.include? counter_type
    @values[table_id]                           = {} unless @values.has_key? table_id
    @values[table_id][operation]                = {} unless @values[table_id].has_key? operation
    @values[table_id][operation][counter_type]  = 0  unless @values[table_id][operation].has_key? counter_type
    @values[table_id][operation][counter_type]  += inc_value
  end

  def increment_uncomitted_success(table_id, operation)
    @uncommitted_values[table_id]            = {} unless @uncommitted_values.has_key? table_id
    @uncommitted_values[table_id][operation] = 0 unless @uncommitted_values[table_id].has_key? operation
    @uncommitted_values[table_id][operation] += 1
  end


  def commit_uncommitted_success_increments
    @uncommitted_values.each do |table_id, operations|
      operations.each do |operation, counter|
        increment(table_id, operation, :events_success, counter)
      end
    end
    @uncommitted_values = {}
  end

  def rollback_uncommitted_success_increments
    @uncommitted_values = {}
  end

  # Write cumulated values to database
  def flush
    if @values != {}
      StatisticCounterConcentrator.get_instance.cumulate(@values)
      @values = {}                                                                # reset cached statistics
    end
  end
end
