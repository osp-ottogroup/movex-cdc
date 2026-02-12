require 'test_helper'

class HousekeepingTest < ActiveSupport::TestCase
  setup do
    # Create victim tables and triggers
    create_victim_structures
    run_with_current_user do
      EventLog.adjust_interval                                                  # Restore possibly wrong setting on table
      create_event_logs_for_test(11)                                            # ensure that at least one interval partition is created
    end
  end

  # Use the DB time instead of Time.now to avoid timezone conflicts
  # @return [Time] the DB sys time
  def time_now
    Database.select_one "SELECT SYSTIMESTAMP FROM DUAL"
  end

  # Remove partitions that are not matching the needed high_value in the past
  def restore_partitioning
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      if MovexCdc::Application.partitioning?
        drop_all_event_logs_partitions_except_1                                 # Only one range partition is remaining
        force_interval_partition_creation(time_now)                             # Ensure that an  d interval partition is created again
      end
    end
  end

  # Create an event log record to force creation of an interval partition
  # @param [Time] created_at The timestamp
  # @return [void]
  def create_event_logs_record(created_at)
    Database.execute "INSERT INTO Event_Logs(ID, Created_At, Table_Id, Operation, DBUser, Payload) VALUES (Event_Logs_Seq.NextVal, TO_DATE(:created_at, 'YYYY-MM-DD HH24:MI:SS'), :table_id, 'I', 'hugo', '\"new\": { \"ID\": 1}')",
                     binds: {created_at: created_at.strftime('%Y-%m-%d %H:%M:%S'), table_id: victim1_table.id }  # Don't use Time directly as bind variable because of timezone drift
  end

  # create an record in Event_Logs to force creation of a new interval partition
  # @param [Time] created_at the time to set the high value of the last partition
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
      Rails.logger.debug('HousekeepingTest.set_high_value_time'){ "high value should by adjusted to an older Time: current=#{current_high_value_time}, expected=#{high_value_time}" }
      log_partition_state(false, 'set_high_value_time before splitting')
      # Database.execute "ALTER TABLE Event_Logs SET INTERVAL ()" if Database.db_version < '13' # Workaround bug in 12.1.0.2 where oldest range partition cannot be dropped if split is done with older high_value (younger partition can be dropped instead)
      partition_name = Database.select_one "SELECT Partition_Name FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' AND Partition_Position = 1"
      # Remove all range partitions except the first partition
      Database.select_all("SELECT Partition_Name FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' AND Interval = 'NO' AND Partition_Position > 1").each do |p|
        Database.execute "ALTER TABLE Event_Logs DROP PARTITION #{p.partition_name}"
      end

      Database.execute "ALTER TABLE Event_Logs SPLIT PARTITION #{partition_name} INTO (
                              PARTITION TestSplit1 VALUES LESS THAN (TO_DATE(' #{high_value_time.strftime('%Y-%m-%d %H:%M:%S')}', 'SYYYY-MM-DD HH24:MI:SS', 'NLS_CALENDAR=GREGORIAN')),
                              PARTITION TestSplit2)"
      Database.execute "ALTER TABLE Event_Logs DROP PARTITION TestSplit2"
      # Database.execute "ALTER TABLE Event_Logs SET INTERVAL (NUMTODSINTERVAL(60,'SECOND'))" if Database.db_version < '13' # Workaround bug in 12.1.0.2 where oldest range partition cannot be dropped if split is done with older high_value (younger partition can be dropped instead)
      log_partition_state(false, 'set_high_value_time after splitting')
    end
    force_interval_partition_creation(high_value_time+interval)                 # create a second partition directly after the first partition (will be with interval = NO)
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
  # @param [Integer] partition_position  the partition position
  # @param [String] high_value The high value if already known
  # @return [Time] the Time from high_value
  def get_time_from_high_value(partition_position, high_value = nil)
    if high_value.nil?
      high_value = Database.select_one "SELECT High_Value FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' AND Partition_Position = #{partition_position}"
    end
    raise "HousekeepingTest: Parameter high_value should not be nil" if high_value.nil?
    hv_string = high_value.split("'")[1].strip                            # extract "2021-04-14 00:00:00" from "TIMESTAMP' 2021-04-14 00:00:00'"
    Time.new(hv_string[0,4].to_i, hv_string[5,2].to_i, hv_string[8,2].to_i, hv_string[11,2].to_i, hv_string[14,2].to_i, hv_string[17,2].to_i)
  end

  # drop all partitions except the last range partition  for test, no matter if they are interval or not
  # Ensure that the high value of the remaining range partiton is at least x days old
  # @return [Integer] the remaining number of partitions (regular 1, but 2 or more for Oracle 12)
  def drop_all_event_logs_partitions_except_1
    sys_time = time_now
    Database.execute "DELETE FROM Event_Logs"

    # drop all partitions above 1 for test, no matter if they are interval or not
    Database.select_all("SELECT Partition_Name
                             FROM   User_Tab_Partitions p
                             WHERE  Table_Name = 'EVENT_LOGS'
                             AND    Partition_Position > 1
                             ORDER BY Partition_Position
                            ").each do |p|
      Database.execute "ALTER TABLE Event_Logs DROP PARTITION #{p.partition_name}"
    end
    part1 = Database.select_first_row("SELECT Partition_Name, High_Value FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS'")
    hv1 = get_time_from_high_value(1, part1.high_value)                         # The HV of the remaining range partition
    # raise "High value of remaining partition #{part1.partition_name} (#{hv1}) is younger than expected " if hv1 > sys_time - Housekeeping.get_instance.max_min_partition_age/4
    high_value_limit = sys_time - Housekeeping.get_instance.max_min_partition_age/4        # The HV should be equal or older than this
    if hv1 > high_value_limit
      Rails.logger.debug('HousekeepingTest.drop_all_event_logs_partitions_except_1') {"High_Value of remaining partition #{part1.partition_name} (#{part1.high_value}) is younger than limit (#{high_value_limit})! Split partition"}
      new_first_partition_name  = "Part_1_#{rand(10000)}"
      new_second_partition_name = "Part_2_#{rand(10000)}"

      Database.execute "ALTER TABLE Event_Logs SPLIT PARTITION #{part1.partition_name} INTO (
                              PARTITION #{new_first_partition_name} VALUES LESS THAN (TO_DATE(' #{high_value_limit.strftime('%Y-%m-%d %H:%M:%S')}', 'SYYYY-MM-DD HH24:MI:SS', 'NLS_CALENDAR=GREGORIAN')),
                              PARTITION #{new_second_partition_name})"
      begin
        Database.execute "ALTER TABLE Event_Logs DROP PARTITION #{new_second_partition_name}"  # this will not work on Oracle 12
      rescue Exception => e
        Rails.logger.warn('HousekeepingTest.drop_all_event_logs_partitions_except_1') { "Partition #{new_second_partition_name} could bot be dropped! #{e.message}" }
      end
    end
    Database.select_one "SELECT COUNT(*) FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS'"
  end

  test "do_housekeeping" do
    Housekeeping.get_instance.do_housekeeping
  end

  test "do_housekeeping with locked partition" do
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      if MovexCdc::Application.partitioning?
        # Drop all partitions except the first one (possibly there are only two range partitions at this point
        initial_partiton_count = drop_all_event_logs_partitions_except_1
        Rails.logger.debug('HousekeepingTest.do_housekeeping with locked partition') { "initial_partiton_count = #{initial_partiton_count}" }
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
        ActiveRecord::Base.transaction do                                       # Hold insert lock on partition until rollback
          create_event_logs_record(last_part_hv + 4 * MovexCdc::Application.config.partition_interval + 1) # This will be the third partition
          create_event_logs_record(last_part_hv + 6 * MovexCdc::Application.config.partition_interval + 1) # This will be the fourth partition
          create_event_logs_record(last_part_hv + 8 * MovexCdc::Application.config.partition_interval + 1) # This will be the fifth partition
          log_partition_state(false, 'Five interval partitions should exist now')
          intermediate_partition_count = Database.select_one("SELECT COUNT(*) FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS'")
          assert_equal 5 + initial_partiton_count, intermediate_partition_count, log_on_failure("There should exist all touched partitions now. Current interval = #{MovexCdc::Application.config.partition_interval}")
          hk_thread = Thread.new do
            Housekeeping.get_instance.do_housekeeping
          end

          raise("Housekeeping not finished until limit") if hk_thread.join(30).nil?
          end_partition_count = Database.select_one("SELECT COUNT(*) FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS'")
          # There should remain: the first partition (if < 12.2), three partitions with pending inserts and the last partition
          remaining_partitions = 4
          assert_equal remaining_partitions, end_partition_count, log_on_failure("Temporary partition with pending insert should not be deleted. Current interval = #{MovexCdc::Application.config.partition_interval}")
        end
        Database.execute "DELETE FROM Event_Logs"                               # Ensure all unprocessable records are removed
        restore_partitioning
      end
    end
  end
end
