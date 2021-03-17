require 'test_helper'

class StatisticCounterConcentratorTest < ActiveSupport::TestCase
  test "create statistics" do
    StatisticCounterConcentrator.get_instance.flush_to_db                       # Flush all pending statistics from memory
    Database.execute "DELETE FROM Statistics"                                   # Ensure valid counters

    [StatisticCounter.new, StatisticCounter.new].each do |sc|
      [tables(:one).id, tables(:two).id].each do |table_id|
        ['I', 'U', 'D'].each do |operation|
          StatisticCounter.supported_counter_types.each do |counter_type|
            sc.increment(table_id, operation, counter_type)
            sc.increment(table_id, operation, counter_type, 3)
          end
        end
        sc.flush
      end
    end

    StatisticCounterConcentrator.get_instance.flush_to_db

    [tables(:one).id, tables(:two).id].each do |table_id|
      ['I', 'U', 'D'].each do |operation|
        StatisticCounter.supported_counter_types.each do |counter_type|
          assert_statistics(expected: 8, table_id: table_id, operation: operation, column_name: counter_type)
        end
      end
    end
  end

end
