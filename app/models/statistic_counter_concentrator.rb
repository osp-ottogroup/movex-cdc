# singleton, cumulates statistics, flush to database is triggered by SystemValidationJob
class StatisticCounterConcentrator
  @@instance = nil
  def self.get_instance
    @@instance = StatisticCounterConcentrator.new if @@instance.nil?
    @@instance
  end

  # called from different threads
  # counter_type = :events_success | :events_failure
  def cumulate(values_hash, counter_type)
    @values_mutex.synchronize do
      values_hash.each do |table_id, operations|
        operations.each do |operation, counter|
          @values[table_id]                           = {} unless @values.has_key? table_id
          @values[table_id][operation]                = {} unless @values[table_id].has_key? operation
          @values[table_id][operation][counter_type]  = 0  unless @values[table_id][operation].has_key? counter_type
          @values[table_id][operation][counter_type] += counter
        end
      end
    end
  end

  def flush_to_db
    @values_mutex.synchronize do
      @values.each do |table_id, operations|
        operations.each do |operation, counter_types|
          counter_types.each do |counter_type, counter|
            Statistic.write_record(table_id: table_id, operation: operation, counter_type => counter)
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
  end
end