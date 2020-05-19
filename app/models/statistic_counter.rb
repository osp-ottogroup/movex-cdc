class StatisticCounter
  # each worker thread should have its own instance

  def initialize
    @values = {}
  end

  # incement events counter no matter if success or error
  def increment(table_id, operation)
    @values[table_id]             = {} unless @values.has_key? table_id
    @values[table_id][operation]  = 0 unless @values[table_id].has_key? operation
    @values[table_id][operation] += 1
  end

  # Write cumulated values to database, mark as success
  def flush_success
    flush(:events_success)
  end

  # Write cumulated values to database, mark as failure
  def flush_failure
    flush(:events_failure)
  end

  # Write cumulated values to database
  def flush(counter_type)
    @values.each do |table_id, operations|
      operations.each do |operation, counter|
        Statistic.write_record(table_id: table_id, operation: operation, counter_type => counter)
      end
    end
    @values = {}                                                                # reset cached statistics
  end
end