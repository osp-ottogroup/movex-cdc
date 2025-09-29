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
        # Ensure that the first partition has a high value less than now - interval and is the only range partition
        first_partition_high_value = get_time_from_high_value(1)
        if first_partition_high_value > Time.now - MovexCdc::Application.config.partition_interval
          Rails.logger.debug('HousekeepingTest.restore_partitioning') { "Adjust high value of first partition because #{first_partition_high_value} is too young" }
          partition_name = Database.select_one "SELECT Partition_Name FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' AND Partition_Position = 1"
          new_first_partition_name  = "Part_1_#{rand(10000)}"
          new_second_partition_name = "Part_2_#{rand(10000)}"

          Database.execute "ALTER TABLE Event_Logs SPLIT PARTITION #{partition_name} INTO (
                              PARTITION #{new_first_partition_name} VALUES LESS THAN (TO_DATE(' #{(Time.now - Housekeeping.get_instance.max_min_partition_age/2).strftime('%Y-%m-%d %H:%M:%S')}', 'SYYYY-MM-DD HH24:MI:SS', 'NLS_CALENDAR=GREGORIAN')),
                              PARTITION #{new_second_partition_name})"
        end

        force_interval_partition_creation(Time.now)                             # Ensure that a interval partition is created again
        assure_last_partition
      end
    end
  end

  def create_event_logs_record(created_at)
    Database.execute "INSERT INTO Event_Logs(ID, Created_At, Table_Id, Operation, DBUser, Payload) VALUES (Event_Logs_Seq.NextVal, TO_DATE(:created_at, 'YYYY-MM-DD HH24:MI:SS'), :table_id, 'I', 'hugo', '\"new\": { \"ID\": 1}')",
                     binds: {created_at: created_at.strftime('%Y-%m-%d %H:%M:%S'), table_id: victim1_table.id }  # Don't use Time directly as bind variable because of timezone drift
  end

  # create an record in Event_Logs to force creation of a new interval partition
  # @param created_at [Time] the time to set the high value of the last partition
  # @return [void]
  def force_interval_partition_creation(created_at)
    ActiveRecord::Base.transaction do
      create_event_logs_record(created_at)
      raise ActiveRecord::Rollback
    end
  end

  # Adjust high value of first partition to an older date
  # @param high_value_time [Time] the new high value
  # @param interval [Integer] the new interval in seconds
  # @param last_partition_time [Time] the time to set the high value of the last partition
  # @return [void]
  def set_high_value_time(high_value_time, interval, last_partition_time)
    MovexCdc::Application.config.partition_interval = interval
    current_high_value_time = get_time_from_high_value(1)
    if current_high_value_time >= high_value_time                                       # high value should by adjusted to an older Time
      Rails.logger.debug('HousekeepingTest.check_partition_interval'){ "high value should by adjusted to an older Time: current=#{current_high_value_time}, expected=#{high_value_time}" }
      log_partition_state(false, 'set_high_value_time before splitting')
      Database.execute "ALTER TABLE Event_Logs SET INTERVAL ()" if Database.db_version < '13' # Workaround bug in 12.1.0.2 where oldest range partition cannot be dropped if split is done with older high_value (younger partition can be dropped instead)
      partition_name = Database.select_one "SELECT Partition_Name FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' AND Partition_Position = 1"
      # Remove all range partitions except the first partition
      Database.select_all("SELECT Partition_Name FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' AND Interval = 'NO' AND Partition_Position > 1").each do |p|
        Database.execute "ALTER TABLE Event_Logs DROP PARTITION #{p.partition_name}"
      end

      Database.execute "ALTER TABLE Event_Logs SPLIT PARTITION #{partition_name} INTO (
                              PARTITION TestSplit1 VALUES LESS THAN (TO_DATE(' #{high_value_time.strftime('%Y-%m-%d %H:%M:%S')}', 'SYYYY-MM-DD HH24:MI:SS', 'NLS_CALENDAR=GREGORIAN')),
                              PARTITION TestSplit2)"
      Database.execute "ALTER TABLE Event_Logs DROP PARTITION TestSplit2"
      Database.execute "ALTER TABLE Event_Logs SET INTERVAL (NUMTODSINTERVAL(60,'SECOND'))" if Database.db_version < '13' # Workaround bug in 12.1.0.2 where oldest range partition cannot be dropped if split is done with older high_value (younger partition can be dropped instead)
      log_partition_state(false, 'set_high_value_time after splitting')
    end
    EventLog.adjust_interval                                                    # adjust in DB according to MovexCdc::Application.config.partition_interval
    force_interval_partition_creation(last_partition_time)                      # ensure existence of at least one interval partition
  end

  # log existing partitions
  # @param console [Boolean] if true log is also written to console
  # @param additional_msg [String] additional message to log
  def log_partition_state(console, additional_msg = '')
    Rails.logger.debug('HousekeepingTest.log_partition_state'){ "------------ Current partitions ------------ #{additional_msg}" }
    Database.select_all("SELECT * FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' ORDER BY Partition_Position").each do |p|
      msg = "Partition #{p.partition_name} Pos=#{p.partition_position} High_Value=#{p.high_value} Interval=#{p.interval} Position=#{p.partition_position}"
      Rails.logger.debug('HousekeepingTest.log_partition_state'){ msg }
      puts msg if console
    end
  end

  # Get Time from Oracle partition high_value
  # @param partition_position [Integer] the partition position
  # @return [Time] the Time from high_value
  def get_time_from_high_value(partition_position)
    high_value = Database.select_one "SELECT High_Value FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' AND Partition_Position = #{partition_position}"
    raise "HousekeepingTest: Parameter high_value should not be nil" if high_value.nil?
    hv_string = high_value.split("'")[1].strip                            # extract "2021-04-14 00:00:00" from "TIMESTAMP' 2021-04-14 00:00:00'"
    Time.new(hv_string[0,4].to_i, hv_string[5,2].to_i, hv_string[8,2].to_i, hv_string[11,2].to_i, hv_string[14,2].to_i, hv_string[17,2].to_i)
  end

  # drop all partitions above 1 for test, no matter if they are interval or not
  def drop_all_event_logs_partitions_except_1
    # drop all partitions above 1 for test, no matter if they are interval or not
    Database.select_all("WITH Partitions AS (SELECT Partition_Name, Interval, Partition_Position
                                                 FROM   User_Tab_Partitions
                                                 WHERE Table_Name = 'EVENT_LOGS'
                                                )
                             SELECT Partition_Name
                             FROM   Partitions p
                             WHERE  Interval = 'YES'
                             OR     (    Interval = 'NO'
                                     /* Do not drop the last range partition to avoid ORA-14758, at least for Rel. 12.1 */
                                     AND Partition_Position != (SELECT MAX(pi.Partition_Position)
                                                                FROM   Partitions pi
^^                                                              WHERE  pi.Interval = 'NO')
                                    )
                             ORDER BY Partition_Position
                            ").each do |p|
      Database.execute "ALTER TABLE Event_Logs DROP PARTITION #{p.partition_name}"
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
        # Drop all partitions except the first one (possibly there are only two range partitions at this point
        drop_all_event_logs_partitions_except_1
        last_part = Database.select_first_row("SELECT Partition_Name, High_Value
                             FROM   User_Tab_Partitions
                             WHERE  Table_Name = 'EVENT_LOGS'
                             ORDER BY Partition_Position DESC")
        last_part_hv = Housekeeping.get_time_from_oracle_high_value(last_part.high_value)
        last_part_hv = last_part_hv.change(offset: '+00:00')                    # Ensure local time as GMT to be sure no conversion happens at parameter binding
        force_interval_partition_creation(last_part_hv+2*MovexCdc::Application.config.partition_interval)  # This will be the second partition
        force_interval_partition_creation(last_part_hv+10*MovexCdc::Application.config.partition_interval)  # This will be the sixth partition
        Database.execute "DELETE FROM Event_Logs"                           # Ensure all partitions are empty
        log_partition_state(false, 'Two interval partitions should exist now')
        assure_last_partition
        ActiveRecord::Base.transaction do                                       # Hold insert lock on partition until rollback
          create_event_logs_record(last_part_hv + 4 * MovexCdc::Application.config.partition_interval + 1) # This will be the third partition
          create_event_logs_record(last_part_hv + 6 * MovexCdc::Application.config.partition_interval + 1) # This will be the fourth partition
          create_event_logs_record(last_part_hv + 8 * MovexCdc::Application.config.partition_interval + 1) # This will be the fifth partition
          log_partition_state(false, 'Five interval partitions should exist now')
          intermediate_partition_count = Database.select_one("SELECT COUNT(*) FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS'")
          assert_equal 6, intermediate_partition_count, log_on_failure("There should exist all touched partitions now. Current interval = #{MovexCdc::Application.config.partition_interval}")
          hk_thread = Thread.new do
            Housekeeping.get_instance.do_housekeeping
          end

          raise("Housekeeping not finished until limit") if hk_thread.join(30).nil?
          end_partition_count = Database.select_one("SELECT COUNT(*) FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS'")
          # There should remain: the first partition, three partitions with pending inserts and the last partition
          assert_equal 5, end_partition_count, log_on_failure("Temporary partition with pending insert should not be deleted. Current interval = #{MovexCdc::Application.config.partition_interval}")
        end
        Database.execute "DELETE FROM Event_Logs"                               # Ensure all unprocessable records are removed
        restore_partitioning
      end
    end
  end

  test "check_partition_interval" do
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      if MovexCdc::Application.partitioning?
        original_interval = MovexCdc::Application.config.partition_interval     # remember the original setting to restore after test
        begin
          do_check = proc do |interval, prev_interval|
            drop_all_event_logs_partitions_except_1                             # possible need to remove the first partition if only range partitions exist
            max_seconds_for_interval_prev= 700000*prev_interval                 # > 1/2 of max. partition count (1024*1024-1) for default interval
            set_high_value_time(Time.now-max_seconds_for_interval_prev, prev_interval, Time.now) # set old high_value to 1/2 of possible partition count and default interval
            Housekeeping.get_instance.check_partition_interval
            log_partition_state(false, 'After check_partitions')                                               # log partitions

            current_hv = get_time_from_high_value(1)
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
          log_partition_state(true, 'Error raised during check_partition')
          raise
        end
        MovexCdc::Application.config.partition_interval = original_interval     # Restore the original setting before the test
        EventLog.adjust_interval                                                # Restore the original interval in table
        restore_partitioning
      end
    end
  end

  test "check_partition_interval with no gaps between min and last partition" do
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      if MovexCdc::Application.partitioning?
        # Choose a high value time for the first partition that is old enough to trigger the adjustment but not too old to exceed the number of allowed partitions
        min_high_value_time = Time.now - Housekeeping.get_instance.max_min_partition_age-3000
        set_high_value_time(min_high_value_time, MovexCdc::Application.config.partition_interval, min_high_value_time+86400)
        drop_all_event_logs_partitions_except_1                                 # Remove all partitions except the MIN partition
        force_interval_partition_creation(min_high_value_time+MovexCdc::Application.config.partition_interval - 1) # Ensure that the next partition is the next possible regarding the interval
        log_partition_state(false, 'before check_partition_interval')
        Housekeeping.get_instance.check_partition_interval
        log_partition_state(false, 'after check_partition_interval')
        assert_equal 2, Database.select_one("SELECT COUNT(*) FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS'"), log_on_failure("There should be two or more partitions")
        current_hv = get_time_from_high_value(1)
        assert current_hv > min_high_value_time+1000, log_on_failure("high value now (#{current_hv}) should be younger than 1/4 related to max. partition count (1024*1024-1) for interval #{MovexCdc::Application.config.partition_interval} seconds. Additional failed tests may occur.")
      end
    end
  end
end
