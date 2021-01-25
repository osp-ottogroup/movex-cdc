require 'test_helper'

class CompressStatisticsTest < ActiveSupport::TestCase

  test "do_compress" do
    def get_sums
      Database.select_first_row "SELECT SUM(events_success)         events_success,
                                        SUM(events_delayed_errors)  events_delayed_errors,
                                        SUM(events_final_errors)    events_final_errors,
                                        SUM(events_d_and_c_retries) events_d_and_c_retries,
                                        SUM(events_delayed_retries) events_delayed_retries
                                 FROM   Statistics
                                "
    end
    sums_before = get_sums

    CompressStatistics.get_instance.do_compress

    younger_14_days = Database.select_first_row("SELECT COUNT(*) records FROM Statistics
                                                 WHERE End_Timestamp > :start_ts AND End_Timestamp < :end_ts",
                                                { start_ts: Time.now-12.days, end_ts: Time.now-8.days})
    assert_equal 3, younger_14_days['records'], 'Number of uncompressed records younger than 14 days'

    older_14_days = Database.select_first_row("SELECT COUNT(*) records FROM Statistics
                                                 WHERE End_Timestamp > :start_ts AND End_Timestamp < :end_ts",
                                                { start_ts: Time.now-22.days, end_ts: Time.now-18.days})
    assert_equal 1, older_14_days['records'], 'Number of compressed records older than 14 days but younger than 3 months'

    older_3_months = Database.select_first_row("SELECT COUNT(*) records FROM Statistics
                                                 WHERE End_Timestamp > :start_ts AND End_Timestamp < :end_ts",
                                                { start_ts: Time.now-102.days, end_ts: Time.now-98.days})
    assert_equal 1, older_3_months['records'], 'Number of compressed records older than 3 months'

    sums_after = get_sums
    assert_equal sums_after['events_success'],          sums_before['events_success'],          'Total number of events_success should not differ after compression'
    assert_equal sums_after['events_delayed_errors'],   sums_before['events_delayed_errors'],   'Total number of events_delayed_errors should not differ after compression'
    assert_equal sums_after['events_final_errors'],     sums_before['events_final_errors'],     'Total number of events_final_errors should not differ after compression'
    assert_equal sums_after['events_d_and_c_retries'],  sums_before['events_d_and_c_retries'],  'Total number of events_d_and_c_retries should not differ after compression'
    assert_equal sums_after['events_delayed_retries'],  sums_before['events_delayed_retries'],  'Total number of events_delayed_retries should not differ after compression'
  end
end
