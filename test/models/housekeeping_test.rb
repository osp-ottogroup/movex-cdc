require 'test_helper'

class HousekeepingTest < ActiveSupport::TestCase

  test "do_housekeeping" do
    Housekeeping.get_instance.do_housekeeping
  end

  test "check_partition_interval" do
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      if Trixx::Application.partitioning?

        log_state = proc do |console|
          Database.select_all("SELECT * FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' ORDER BY Partition_Position").each do |p|
            msg = "Partition #{p.partition_name} Pos=#{p.partition_position} High_Value=#{p.high_value} Interval=#{p.interval} Position=#{p.partition_position}"
            Rails.logger.debug msg
            puts msg if console
          end
        end

        begin
          get_time_from_high_value = proc do
            high_value = Database.select_one "SELECT High_Value FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' AND Partition_Position = 1"
            raise "HousekeepingTest: Parameter high_value should not be nil" if high_value.nil?
            hv_string = high_value.split("'")[1].strip                            # extract "2021-04-14 00:00:00" from "TIMESTAMP' 2021-04-14 00:00:00'"
            Time.new(hv_string[0,4].to_i, hv_string[5,2].to_i, hv_string[8,2].to_i, hv_string[11,2].to_i, hv_string[14,2].to_i, hv_string[17,2].to_i)
          end

          # Adjust high value of first partition to an older date
          set_high_value = proc do |high_value_time, interval|
            Trixx::Application.config.trixx_partition_interval = interval
            current_high_value_time = get_time_from_high_value.call
            if current_high_value_time >= high_value_time                 # high value should by adjusted to an older Time
              Rails.logger.debug "high value should by adjusted to an older Time: current=#{current_high_value_time}, expected=#{high_value_time}"
              log_state.call(false)                                             # log partitions
              Database.execute "ALTER TABLE Event_Logs SET INTERVAL ()"         # Workaround bug in 12.1.0.2 where oldest range partition cannot be dropped if split is done with older high_value (younger partition can be dropped instead)
              partition_name = Database.select_one "SELECT Partition_Name FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' AND Partition_Position = 1"
              # Remove all range partitions except the MIN partition
              Database.select_all("SELECT Partition_Name FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' AND Partition_Position != 1").each do |p|
                Database.execute "ALTER TABLE Event_Logs DROP PARTITION #{p.partition_name}"
              end

              Database.execute "ALTER TABLE Event_Logs SPLIT PARTITION #{partition_name} INTO (
                              PARTITION TestSplit1 VALUES LESS THAN (TO_DATE(' #{high_value_time.strftime('%Y-%m-%d %H:%M:%S')}', 'SYYYY-MM-DD HH24:MI:SS', 'NLS_CALENDAR=GREGORIAN')),
                              PARTITION TestSplit2)"
              Database.execute "ALTER TABLE Event_Logs RENAME PARTITION TestSplit1 TO MIN"
              Database.execute "ALTER TABLE Event_Logs DROP PARTITION TestSplit2"
              log_state.call(false)                                             # log partitions
            end
            EventLog.adjust_interval                                            # adjust in DB according to Trixx::Application.config.trixx_partition_interval

            # ensure existence of at least one interval partition
            ActiveRecord::Base.transaction do
              Database.execute "INSERT INTO Event_Logs(ID, Created_At, Table_Id, Operation, DBUser, Payload) VALUES (Event_Logs_Seq.NextVal, TO_DATE(:created_at, 'YYYY-MM-DD HH24:MI:SS'), 5, 'I', 'hugo', 'hugo')",
                                 created_at: Time.now.strftime('%Y-%m-%d %H:%M:%S')  # Don't use Time directly as bind variable because of timezone drift
              raise ActiveRecord::Rollback
            end

          end

          do_check = proc do |interval, prev_interval|
            max_minutes_for_interval_prev= 700000*prev_interval                 # > 1/2 of max. partition count (1024*1024-1) for default interval
            set_high_value.call(Time.now-max_minutes_for_interval_prev*60, prev_interval) # set old high_value to 1/2 of possible partition count and default interval
            Housekeeping.get_instance.check_partition_interval
            log_state.call(false)                                               # log partitions

            current_hv = get_time_from_high_value.call
            max_expected_minutes_for_interval = (1024*1024)/6*interval          # < 1/4 of max. partition count (1024*1024-1) for interval
            min_expected_hv = Time.now-max_expected_minutes_for_interval*60
            assert current_hv > min_expected_hv, "high value now (#{current_hv}) should be younger than 1/4 related to max. partition count (1024*1024-1) for interval #{interval} minutes (#{min_expected_hv})"
          end

          # take into account that Time cannot be before ca. 1729-02-15
          do_check.call(1,    10)                                               # should change high_value and interval
          do_check.call(10,   10)                                               # should change only high_value
          do_check.call(2000, 10)                                               # should change high_value and interval
          do_check.call(10,   2000)                                             # should change high_value and interval
          do_check.call(2000, 200)                                              # should change only high_value

        rescue
          log_state.call(true)                                                  # log partitions
          raise
        end
      end
    end
  end
end
