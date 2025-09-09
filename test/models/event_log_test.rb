require 'test_helper'

class EventLogTest < ActiveSupport::TestCase

  # create and rollback one record to provoke partition creation
  def ensure_partition_exists
    ActiveRecord::Base.transaction do
      EventLog.new(id: 8732742944, table_id: 0, operation: 'I', dbuser: 'Hugo', payload: 'Dummy').save!
      raise ActiveRecord::Rollback, "Record should not persist!"
    end
  end

  test "select event log" do
    assert_nothing_raised do
      event_logs = EventLog.all
    end
  end

  test "adjust_max_simultaneous_transactions" do
    assert_nothing_raised do
      case MovexCdc::Application.config.db_type
      when 'ORACLE' then
        get_ini_trans = proc do
          if MovexCdc::Application.partitioning?
            Database.select_one "SELECT def_ini_trans from User_Part_Tables WHERE Table_Name ='EVENT_LOGS'"
          else
            Database.select_one "SELECT ini_trans from User_Tables WHERE Table_Name ='EVENT_LOGS'"
          end
        end
        current_value = get_ini_trans.call
        current_value = 2 if current_value < 2    # Minimum value is 2 for index to avoid ORA-02207
        MovexCdc::Application.config.max_simultaneous_transactions = current_value + 5
        EventLog.adjust_max_simultaneous_transactions
        changed_value = get_ini_trans.call
        if MovexCdc::Application.config.db_sys_user == 'SYS'
          assert_equal current_value + 5, changed_value, log_on_failure('INI_TRANS should have been changed')
        else
          puts "EventLogTest.adjust_max_simultaneous_transactions: Check INI_TRANS suppressed for autonomous DB due to fixed values, see SR 3-32960331791"
        end
        MovexCdc::Application.config.max_simultaneous_transactions = current_value
        EventLog.adjust_max_simultaneous_transactions                               # Restore original state
      end
    end
  end

  test "adjust interval" do
    assert_nothing_raised do
      case MovexCdc::Application.config.db_type
      when 'ORACLE' then
        if MovexCdc::Application.partitioning?
          current_interval = EventLog.current_interval_seconds
          CHANGE_DIFF = 300
          MovexCdc::Application.config.partition_interval = current_interval + CHANGE_DIFF
          EventLog.adjust_interval
          new_interval = EventLog.current_interval_seconds
          assert_equal current_interval + CHANGE_DIFF, new_interval, log_on_failure('Interval should have been changed')
          MovexCdc::Application.config.partition_interval = current_interval + 120000
          EventLog.adjust_interval                                                # Test a higher value
          MovexCdc::Application.config.partition_interval = current_interval
          EventLog.adjust_interval                                                # restore original state
        end
      end
    end
  end

  test "health_check_status" do
    EventLog.health_check_status
  end

  test "check_and_drop_partition" do
    # Tested by housekeeping_test at first
    # TODO: test for middle partition
    ensure_partition_exists
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      if MovexCdc::Application.partitioning?
        max_partition_name = Database.select_one "SELECT MAX(Partition_Name) KEEP (DENSE_RANK LAST ORDER BY Partition_Position) FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS'"
        assert !EventLog.check_and_drop_partition(max_partition_name, 'Test'), log_on_failure("Max. partition should not be dropped")
      end
    end
  end

  test "partition_allowed_for_drop" do
    ensure_partition_exists
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      if MovexCdc::Application.partitioning?
        max_part = Database.select_first_row "WITH Parts AS (SELECT Partition_Name, Partition_Position, high_value
                                                                FROM User_Tab_Partitions
                                                                WHERE Table_Name = 'EVENT_LOGS')
                                                 SELECT *
                                                 FROM   Parts
                                                 WHERE  Partition_Position = (SELECT MAX(Partition_Position) FROM Parts)
                                                "
        assert !EventLog.partition_allowed_for_drop?(max_part.partition_name, max_part.partition_position, max_part.high_value, 'Test'), log_on_failure("Max. partition should not be dropped")
      end
    end
  end

end
