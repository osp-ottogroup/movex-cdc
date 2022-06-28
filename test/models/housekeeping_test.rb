require 'test_helper'

class HousekeepingTest < ActiveSupport::TestCase
  setup do
    # Create victim tables and triggers
    create_victim_structures
    run_with_current_user { create_event_logs_for_test(11) }                    # ensure that at least one interval partition is created
  end

  # Ensure that last partition remains existing
  def assure_last_partition
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      if MovexCdc::Application.partitioning?
        part_count = Database.select_one("SELECT COUNT(*) FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS'")
        if part_count < 2
          Database.select_all("SELECT Partition_Name, High_Value, Interval FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' ORDER BY Partition_Position").each do |part|
            Rails.logger.debug('HousekeepingTest.assure_last_partition') {"Partition #{part.part_name} high value: #{part.high_value} interval:#{part.interval}"}
          end
          assert false, log_on_failure("There should remain at least two partitions")
        end
      end
    end
  end

  # Remove partitions that are not matching the needed high_value in the past
  def restore_partitioning
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      if MovexCdc::Application.partitioning?
        Database.select_all("SELECT Partition_Name, High_Value, Interval
                             FROM   User_Tab_Partitions
                             WHERE  Table_Name = 'EVENT_LOGS'
                             AND    Partition_Position > 1
                             ORDER BY Partition_Position DESC
                            ").each do |part|
          begin
            Rails.logger.debug('HousekeepingTest.restore_partitioning') { "Try to drop partition #{part.partition_name} with high value #{part.high_value}"}
            Database.execute "ALTER TABLE Event_Logs DROP PARTITION #{part.partition_name}"
          rescue Exception => e
            Rails.logger.debug('HousekeepingTest.restore_partitioning') { "Error during DROP PARTITION #{part.partition_name} #{e.class}:#{e.message}"}
          end
        end
        # Ensure that a interval partition is created again
        Database.execute "INSERT INTO Event_Logs (ID, Table_ID, Operation, DBUser, Payload, Created_At)
                    VALUES (Event_Logs_Seq.NextVal, :table_id, 'I', 'HUGO', '{}', :created_at)
                   ", binds: {table_id: victim1_table.id, created_at: Time.now.change(offset: '+00:00')}
        assure_last_partition
      end
    end
  end

  test "do_housekeeping" do
    Housekeeping.get_instance.do_housekeeping
    assure_last_partition
  end

  test "do_housekeeping with locked partition" do
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      if MovexCdc::Application.partitioning?
        # Drop all partitiones except the first one (possibly there are only two range partitions at this point)
        last_part = Database.select_first_row("SELECT Partition_Name, High_Value
                             FROM   User_Tab_Partitions
                             WHERE  Table_Name = 'EVENT_LOGS'
                             ORDER BY Partition_Position DESC")
        last_part_hv = Housekeeping.get_time_from_oracle_high_value(last_part.high_value)
        last_part_hv = last_part_hv.change(offset: '+00:00')                    # Ensure local time as GMT to be sure no conversion happens at parameter binding
        # Ensure that a current interval partition exists
        Database.execute "INSERT INTO Event_Logs (ID, Table_ID, Operation, DBUser, Payload, Created_At)
                    VALUES (Event_Logs_Seq.NextVal, :table_id, 'I', 'HUGO', '{}', :created_at)
                   ", binds: {table_id: victim1_table.id, created_at: last_part_hv+122}

        Database.execute "DELETE FROM Event_Logs"                               # Ensure all partitions are empty
        Housekeeping.get_instance.do_housekeeping                               # Ensure old partitions are removed
        assure_last_partition
        start_partition_count = Database.select_one("SELECT COUNT(*) FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS'")
        ActiveRecord::Base.transaction do                                       # Hold insert lock on partition until rollback
          # create a partition 20 days back that should not exists before
          Database.execute "INSERT INTO Event_Logs (ID, Table_ID, Operation, DBUser, Payload, Created_At)
                    VALUES (Event_Logs_Seq.NextVal, :table_id, 'I', 'HUGO', '{}', :created_at)
                   ", binds: {table_id: victim1_table.id, created_at: last_part_hv+61}

          hk_thread = Thread.new do
            Housekeeping.get_instance.do_housekeeping
          end

          raise("Housekeeping not finished until limit") if hk_thread.join(30).nil?
          end_partition_count = Database.select_one("SELECT COUNT(*) FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS'")
          assert_equal start_partition_count+1, end_partition_count, log_on_failure("Temporary partition with pending insert should not be deleted. Current interval = #{MovexCdc::Application.config.partition_interval}")
        end
        Database.execute "DELETE FROM Event_Logs"                               # Ensure all unprocessabe records are removed
        restore_partitioning
      end
    end
  end

  test "check_partition_interval" do
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      if MovexCdc::Application.partitioning?
        original_interval = MovexCdc::Application.config.partition_interval     # remember the original setting to restore after test
        log_state = proc do |console|
          Database.select_all("SELECT * FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' ORDER BY Partition_Position").each do |p|
            msg = "Partition #{p.partition_name} Pos=#{p.partition_position} High_Value=#{p.high_value} Interval=#{p.interval} Position=#{p.partition_position}"
            Rails.logger.debug('HousekeepingTest.check_partition_interval'){ msg }
            puts msg if console
          end
        end

        begin
          get_time_from_high_value = proc do |partition_position|
            high_value = Database.select_one "SELECT High_Value FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' AND Partition_Position = #{partition_position}"
            raise "HousekeepingTest: Parameter high_value should not be nil" if high_value.nil?
            hv_string = high_value.split("'")[1].strip                            # extract "2021-04-14 00:00:00" from "TIMESTAMP' 2021-04-14 00:00:00'"
            Time.new(hv_string[0,4].to_i, hv_string[5,2].to_i, hv_string[8,2].to_i, hv_string[11,2].to_i, hv_string[14,2].to_i, hv_string[17,2].to_i)
          end

          # Adjust high value of first partition to an older date
          set_high_value = proc do |high_value_time, interval|
            MovexCdc::Application.config.partition_interval = interval
            current_high_value_time = get_time_from_high_value.call(1)
            if current_high_value_time >= high_value_time                 # high value should by adjusted to an older Time
              Rails.logger.debug('HousekeepingTest.check_partition_interval'){ "high value should by adjusted to an older Time: current=#{current_high_value_time}, expected=#{high_value_time}" }
              log_state.call(false)                                             # log partitions
              Database.execute "ALTER TABLE Event_Logs SET INTERVAL ()"         # Workaround bug in 12.1.0.2 where oldest range partition cannot be dropped if split is done with older high_value (younger partition can be dropped instead)
              partition_name = Database.select_one "SELECT Partition_Name FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' AND Partition_Position = 1"
              # Remove all range partitions except the first partition
              Database.select_all("SELECT Partition_Name FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' AND Interval = 'NO' AND Partition_Position > 1").each do |p|
                Database.execute "ALTER TABLE Event_Logs DROP PARTITION #{p.partition_name}"
              end

              Database.execute "ALTER TABLE Event_Logs SPLIT PARTITION #{partition_name} INTO (
                              PARTITION TestSplit1 VALUES LESS THAN (TO_DATE(' #{high_value_time.strftime('%Y-%m-%d %H:%M:%S')}', 'SYYYY-MM-DD HH24:MI:SS', 'NLS_CALENDAR=GREGORIAN')),
                              PARTITION TestSplit2)"
              Database.execute "ALTER TABLE Event_Logs DROP PARTITION TestSplit2"
              log_state.call(false)                                             # log partitions
            end
            EventLog.adjust_interval                                            # adjust in DB according to MovexCdc::Application.config.partition_interval

            # ensure existence of at least one interval partition
            ActiveRecord::Base.transaction do
              Database.execute "INSERT INTO Event_Logs(ID, Created_At, Table_Id, Operation, DBUser, Payload) VALUES (Event_Logs_Seq.NextVal, TO_DATE(:created_at, 'YYYY-MM-DD HH24:MI:SS'), 5, 'I', 'hugo', 'hugo')",
                               binds: { created_at: Time.now.strftime('%Y-%m-%d %H:%M:%S') }  # Don't use Time directly as bind variable because of timezone drift
              raise ActiveRecord::Rollback
            end

          end

          do_check = proc do |interval, prev_interval|
            # delete all partitions above 1 for test, no matter if they are interval or not
            Database.select_all("SELECT Partition_Name FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' AND Interval = 'YES' AND Partition_Position > 1").each do |p|
              Database.execute "ALTER TABLE Event_Logs DROP PARTITION #{p.partition_name}"
            end
            # possible need to remove the first partition if only range partitions exist

            max_seconds_for_interval_prev= 700000*prev_interval                 # > 1/2 of max. partition count (1024*1024-1) for default interval
            set_high_value.call(Time.now-max_seconds_for_interval_prev, prev_interval) # set old high_value to 1/2 of possible partition count and default interval
            Housekeeping.get_instance.check_partition_interval
            log_state.call(false)                                               # log partitions

            current_hv = get_time_from_high_value.call(1)
            max_expected_seconds_for_interval = (1024*1024)*10*interval          # < 1/4 of max. partition count (1024*1024-1) for interval
            min_expected_hv = Time.now-max_expected_seconds_for_interval
            assert current_hv > min_expected_hv, log_on_failure("high value now (#{current_hv}) should be younger than 1/4 related to max. partition count (1024*1024-1) for interval #{interval} seconds (#{min_expected_hv})")
          end

          # take into account that Time cannot be before ca. 1729-02-15
          do_check.call(60,     600)                                            # should change high_value and interval
          do_check.call(600,    600)                                            # should change only high_value
          do_check.call(120000, 600)                                            # should change high_value and interval
          do_check.call(600,    120000)                                         # should change high_value and interval
          do_check.call(120000, 12000)                                          # should change only high_value

        rescue
          log_state.call(true)                                                  # log partitions
          raise
        end
        MovexCdc::Application.config.partition_interval = original_interval     # Restore the original setting before the test
        EventLog.adjust_interval                                                # Restore the original interval in table
        restore_partitioning
      end
    end
  end
end
