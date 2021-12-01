require 'test_helper'

class HousekeepingTest < ActiveSupport::TestCase
  setup do
    # Create victim tables and triggers
    create_victim_structures
    create_event_logs_for_test(11)                                              # ensure that at least one interval partition is created
  end

  # Ensure that last partition remains existing
  def assure_last_partition
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      if Trixx::Application.partitioning?
        assert 2 <= Database.select_one("SELECT COUNT(*) FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS'"),
               "There should remain at least two partitions"
      end
    end
  end

  test "do_housekeeping" do
    Housekeeping.get_instance.do_housekeeping
    assure_last_partition
  end

  test "check_partition_interval" do
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      if Trixx::Application.partitioning?
        Database.execute "DELETE FROM Event_Logs"                               # Ensure partitions are empty to allow houskeeping
        log_state = proc do |console|
          Database.select_all("SELECT * FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' ORDER BY Partition_Position").each do |p|
            msg = "Partition #{p.partition_name} Pos=#{p.partition_position} High_Value=#{p.high_value} Interval=#{p.interval} Position=#{p.partition_position}"
            Rails.logger.debug msg
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
            Trixx::Application.config.trixx_partition_interval = interval
            current_high_value_time = get_time_from_high_value.call(1)
            if current_high_value_time >= high_value_time                 # high value should by adjusted to an older Time
              Rails.logger.debug "high value should by adjusted to an older Time: current=#{current_high_value_time}, expected=#{high_value_time}"
              log_state.call(false)                                             # log partitions
              Database.execute "ALTER TABLE Event_Logs SET INTERVAL ()"         # Workaround bug in 12.1.0.2 where oldest range partition cannot be dropped if split is done with older high_value (younger partition can be dropped instead)
              partition_name = Database.select_one "SELECT Partition_Name FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' AND Partition_Position = 1"
              # Remove all range partitions except the first partition
              Database.select_all("SELECT Partition_Name FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' AND Interval = 'NO' AND Partition_Position > 1").each do |p|
                EventLog.check_and_drop_partition(p.partition_name, "test check_partition_interval")
                #Database.execute "ALTER TABLE Event_Logs DROP PARTITION #{p.partition_name}"
              end

              Database.execute "ALTER TABLE Event_Logs SPLIT PARTITION #{partition_name} INTO (
                              PARTITION TestSplit1 VALUES LESS THAN (TO_DATE(' #{high_value_time.strftime('%Y-%m-%d %H:%M:%S')}', 'SYYYY-MM-DD HH24:MI:SS', 'NLS_CALENDAR=GREGORIAN')),
                              PARTITION TestSplit2)"
              EventLog.check_and_drop_partition('TESTSPLIT2', "test check_partition_interval")
              # Database.execute "ALTER TABLE Event_Logs DROP PARTITION TestSplit2"
              log_state.call(false)                                             # log partitions
            end
            EventLog.adjust_interval                                            # adjust in DB according to Trixx::Application.config.trixx_partition_interval

            # ensure existence of at least one interval partition
            ActiveRecord::Base.transaction do
              max_partition_position = Database.select_one "SELECT Max(Partition_Position) FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS'"
              Database.execute "INSERT INTO Event_Logs(ID, Created_At, Table_Id, Operation, DBUser, Payload) VALUES (Event_Logs_Seq.NextVal, TO_DATE(:created_at, 'YYYY-MM-DD HH24:MI:SS'), 5, 'I', 'hugo', 'hugo')",
                                 created_at: (get_time_from_high_value.call(max_partition_position) + 2).strftime('%Y-%m-%d %H:%M:%S')  # Don't use Time directly as bind variable because of timezone drift
              raise ActiveRecord::Rollback
            end

          end

          do_check = proc do |interval, prev_interval|
            max_seconds_for_interval_prev= 700000*prev_interval                 # > 1/2 of max. partition count (1024*1024-1) for default interval
            set_high_value.call(Time.now-max_seconds_for_interval_prev, prev_interval) # set old high_value to 1/2 of possible partition count and default interval
            Housekeeping.get_instance.check_partition_interval
            log_state.call(false)                                               # log partitions

            current_hv = get_time_from_high_value.call(1)
            max_expected_seconds_for_interval = (1024*1024)*10*interval          # < 1/4 of max. partition count (1024*1024-1) for interval
            min_expected_hv = Time.now-max_expected_seconds_for_interval
            assert current_hv > min_expected_hv, "high value now (#{current_hv}) should be younger than 1/4 related to max. partition count (1024*1024-1) for interval #{interval} seconds (#{min_expected_hv})"
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
      end
    end
    assure_last_partition
  end
end
