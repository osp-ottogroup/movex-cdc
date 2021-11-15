require 'test_helper'

class EventLogTest < ActiveSupport::TestCase

  test "select event log" do
    event_logs = EventLog.all
  end

  test "adjust_max_simultaneous_transactions" do
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      get_ini_trans = proc do
        if Trixx::Application.partitioning?
          Database.select_one "SELECT def_ini_trans from User_Part_Tables WHERE Table_Name ='EVENT_LOGS'"
        else
          Database.select_one "SELECT ini_trans from User_Tables WHERE Table_Name ='EVENT_LOGS'"
        end
      end
      current_value = get_ini_trans.call
      Trixx::Application.config.trixx_max_simultaneous_transactions = current_value + 5
      EventLog.adjust_max_simultaneous_transactions
      changed_value = get_ini_trans.call
      assert_equal current_value + 5, changed_value, 'INI_TRANS should have been changed'
      Trixx::Application.config.trixx_max_simultaneous_transactions = current_value
      EventLog.adjust_max_simultaneous_transactions                               # Restore original state
    end
  end

  test "adjust interval" do
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      if Trixx::Application.partitioning?
        current_interval = EventLog.current_interval_seconds
        CHANGE_DIFF = 300
        Trixx::Application.config.trixx_partition_interval = current_interval + CHANGE_DIFF
        EventLog.adjust_interval
        new_interval = EventLog.current_interval_seconds
        assert_equal current_interval + CHANGE_DIFF, new_interval, 'Interval should have been changed'
        Trixx::Application.config.trixx_partition_interval = current_interval + 120000
        EventLog.adjust_interval                                                # Test a higher value
        Trixx::Application.config.trixx_partition_interval = current_interval
        EventLog.adjust_interval                                                # restore original state
      end
    end
  end

end
