require 'test_helper'

class HousekeepingTest < ActiveSupport::TestCase

  test "do_housekeeping" do
    Housekeeping.get_instance.do_housekeeping
  end



  test "check_partition_interval" do
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      current_interval = proc do
        Database.select_one "SELECT TO_NUMBER(SUBSTR(Interval, INSTR(Interval, '(')+1, INSTR(Interval, ',')-INSTR(Interval, '(')-1)) FROM User_Part_Tables WHERE Table_Name = 'EVENT_LOGS'"
      end

      get_time_from_high_value = proc do
        high_value = Database.select_one "SELECT High_Value FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' AND Partition_Name = 'MIN'"
        raise "HousekeepingTest: Parameter high_value should not be nil" if high_value.nil?
        hv_string = high_value.split("'")[1].strip                            # extract "2021-04-14 00:00:00" from "TIMESTAMP' 2021-04-14 00:00:00'"
        Time.new(hv_string[0,4].to_i, hv_string[5,2].to_i, hv_string[8,2].to_i, hv_string[11,2].to_i, hv_string[14,2].to_i, hv_string[17,2].to_i)
      end

      set_high_value_and_interval = proc do |high_value_time, interval|
        Database.execute "ALTER TABLE Event_Logs MODIFY PARTITION BY RANGE (Created_At) INTERVAL( NUMTODSINTERVAL(#{interval},'MINUTE'))
                            ( PARTITION MIN VALUES LESS THAN (TO_DATE(' #{high_value_time.strftime('%Y-%m-%d %H:%M:%S')}', 'SYYYY-MM-DD HH24:MI:SS', 'NLS_CALENDAR=GREGORIAN')) )
                            ONLINE"
      end

      do_check = proc do |interval, prev_interval|
        max_minutes_for_interval_prev= 700000*prev_interval                                 # > 1/2 of max. partition count (1024*1024-1) for default interval
        set_high_value_and_interval.call(Time.now-max_minutes_for_interval_prev*60, prev_interval) # set old high_value to 1/2 of possible partition count and default interval
        Trixx::Application.config.trixx_partition_interval = interval
        Housekeeping.get_instance.check_partition_interval

        current_hv = get_time_from_high_value.call
        max_expected_minutes_for_interval = (1024*1024)/6*interval                              # < 1/4 of max. partition count (1024*1024-1) for interval
        min_expected_hv = Time.now-max_expected_minutes_for_interval*60
        assert current_hv > min_expected_hv, "high value now (#{current_hv}) should be younger than 1/4 related to max. partition count (1024*1024-1) for interval #{interval} minutes (#{min_expected_hv})"
        assert_equal interval, current_interval.call, 'Set of interval expected'
      end

      # take into account that Time cannot be before ca. 1729-02-15
      do_check.call(1,    10)                                                   # should change high_value and interval
      do_check.call(10,   10)                                                   # should change only high_value
      do_check.call(2000, 10)                                                   # should change high_value and interval
      do_check.call(10,   2000)                                                 # should change high_value and interval
      do_check.call(2000, 200)                                                  # should change only high_value
    end
  end
end
