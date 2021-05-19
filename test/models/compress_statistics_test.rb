require 'test_helper'

class CompressStatisticsTest < ActiveSupport::TestCase

  test "do_compress" do
    def insert_statistics(amount, operation, end_timestamp)
      1.upto(amount) do
        Statistic.new(
          table_id: tables_table.id,
          operation: operation,
          events_success: 4,
          end_timestamp: end_timestamp,
          events_delayed_errors: 5,
          events_final_errors: 6,
          events_d_and_c_retries: 7,
          events_delayed_retries: 8
      ).save!

      end
    end

    def get_sums
      Database.select_first_row "SELECT SUM(events_success)         events_success,
                                        SUM(events_delayed_errors)  events_delayed_errors,
                                        SUM(events_final_errors)    events_final_errors,
                                        SUM(events_d_and_c_retries) events_d_and_c_retries,
                                        SUM(events_delayed_retries) events_delayed_retries
                                 FROM   Statistics
                                "
    end

    def get_single_values(operation, end_timestamp)
      Database.select_first_row("SELECT COUNT(*) records
                                 FROM   Statistics
                                 WHERE  Operation = :operation
                                 AND    End_Timestamp > :start_ts AND End_Timestamp < :end_ts",
                                { operation: operation, start_ts: end_timestamp-2.days, end_ts: end_timestamp+2.days}
      )
    end

    # prepare test
    insert_statistics(3, 'I', Time.now - 10.days)
    insert_statistics(5, 'U', Time.now - 10.days)
    insert_statistics(3, 'I', Time.now - 20.days)
    insert_statistics(8, 'U', Time.now - 20.days)
    insert_statistics(3, 'I', Time.now - 100.days)
    insert_statistics(25,'U', Time.now - 100.days)

    sums_before = get_sums

    CompressStatistics.get_instance.do_compress

    assert_equal 3, get_single_values('I', Time.now-10.days)['records'], 'Number of uncompressed insert records younger than 14 days'
    assert_equal 5, get_single_values('U', Time.now-10.days)['records'], 'Number of uncompressed update records younger than 14 days'
    assert_equal 1, get_single_values('I', Time.now-20.days)['records'], 'Number of compressed insert records older than 14 days but younger than 3 months'
    assert_equal 1, get_single_values('U', Time.now-20.days)['records'], 'Number of compressed update records older than 14 days but younger than 3 months'
    assert_equal 1, get_single_values('I', Time.now-100.days)['records'], 'Number of compressed insert records older than 3 months'
    assert_equal 1, get_single_values('U', Time.now-100.days)['records'], 'Number of compressed update records older than 3 months'

    sums_after = get_sums
    assert_equal sums_after['events_success'],          sums_before['events_success'],          'Total number of events_success should not differ after compression'
    assert_equal sums_after['events_delayed_errors'],   sums_before['events_delayed_errors'],   'Total number of events_delayed_errors should not differ after compression'
    assert_equal sums_after['events_final_errors'],     sums_before['events_final_errors'],     'Total number of events_final_errors should not differ after compression'
    assert_equal sums_after['events_d_and_c_retries'],  sums_before['events_d_and_c_retries'],  'Total number of events_d_and_c_retries should not differ after compression'
    assert_equal sums_after['events_delayed_retries'],  sums_before['events_delayed_retries'],  'Total number of events_delayed_retries should not differ after compression'
  end
end
