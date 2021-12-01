class Housekeeping

  @@instance = nil
  def self.get_instance
    @@instance = Housekeeping.new if @@instance.nil?
    @@instance
  end

  def do_housekeeping
    if @last_housekeeping_started.nil?
      Rails.logger.debug "Housekeeping.do_housekeeping: Start housekeeping"
      do_housekeeping_internal
    else
      Rails.logger.error "Housekeeping.do_housekeeping: Last run started at #{@last_housekeeping_started} not yet finished!"
    end
  end

  # Ensure distance between first non-interval and current partition remains valid
  def check_partition_interval
    if @last_partition_interval_check_started.nil?
      Rails.logger.debug "Housekeeping.check_partition_interval: Start check"
      check_partition_interval_internal
    else
      Rails.logger.error "Housekeeping.check_partition_interval: Last run started at #{@last_partition_interval_check_started} not yet finished!"
    end
  end



  private
  def initialize                                                                # get singleton by get_instance only
    @last_housekeeping_started = nil                                            # semaphore to prevent multiple execution
    @last_partition_interval_check_started = nil                                # semaphore to prevent multiple execution
  end

  def do_housekeeping_internal
    @last_housekeeping_started = Time.now
    log_partitions                                                              # log all existing partitions

    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      # check all partitions for deletion except the youngest one, no matter if they are interval or not
      if Trixx::Application.partitioning?
        partitions_to_check = Database.select_all "\
          WITH Partitions AS (SELECT Partition_Name, Partition_Position, Interval
                              FROM   User_Tab_Partitions
                              WHERE  Table_Name = 'EVENT_LOGS'
                             )
          SELECT p.Partition_Name, p.Partition_Position, stats.Interval_Count, stats.Max_Partition_Position
          FROM   Partitions p
          CROSS JOIN (SELECT SUM(DECODE(Interval, 'YES', 1, 0)) Interval_Count, MAX(Partition_Position) Max_Partition_Position
                      FROM Partitions
                     ) stats
          /* do not check the youngest interval (should survive) and the youngest range partition (will raise ORA-14758) for deletion */
          WHERE  Partition_Position != (SELECT MAX(pi.Partition_Position) FROM Partitions pi WHERE pi.Interval = p.Interval)
          ORDER BY Partition_Position
        "
        partitions_to_check.each do |part|
          # if only range partitions exists (no interval) than preserve the youngest two range partitions (because the first partition is not scanned by worker)
          if part.interval_count > 0 || ( part.partition_position < part.max_partition_position - 2 )
            EventLog.check_and_drop_partition(part['partition_name'], 'Housekeeping.do_housekeeping_internal')
          end
        end
      end
    end

  ensure
    @last_housekeeping_started = nil
  end


  # check if high value of first non-interval partition must be lifted up because between first and last partition only 1024*1024-1 possible partitions are supported by Oracle
  def check_partition_interval_internal
    @last_partition_interval_check_started = Time.now

    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      if Trixx::Application.partitioning?

        get_time_from_high_value = proc do |high_value|
          raise "Housekeeping.get_time_from_high_value: Parameter high_value should not be nil" if high_value.nil?
          hv_string = high_value.split("'")[1].strip                            # extract "2021-04-14 00:00:00" from "TIMESTAMP' 2021-04-14 00:00:00'"
          Time.new(hv_string[0,4].to_i, hv_string[5,2].to_i, hv_string[8,2].to_i, hv_string[11,2].to_i, hv_string[14,2].to_i, hv_string[17,2].to_i)
        end

        max_distance_seconds = (1024*1024-1) * Trixx::Application.config.trixx_partition_interval / 4 # 1/4 of allowed number of possible partitions
        max_distance_seconds = 1440*365*60 if max_distance_seconds > 1440*365*60 # largest distance for oldest partition is one year

        part1 = Database.select_first_row "SELECT Partition_Name, High_Value, Partition_Position FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' AND Partition_Position = 1"
        raise "No oldest partition found for table Event_Logs" if part1.nil?
        min_time =  get_time_from_high_value.call(part1.high_value)
        Rails.logger.debug "High value of oldest partition for Event_Logs is #{min_time}"
        compare_time = Time.now - 100*86400                                     # 100 days back
        Database.select_all("SELECT High_Value FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' AND Partition_Position > 1").each do |p|
          part_time = get_time_from_high_value.call(p.high_value)
          compare_time = part_time if part_time < compare_time                  # get oldest partition high value
        end
        Rails.logger.debug "High value of second oldest partition for Event_Logs is #{compare_time}"
        if compare_time - Time.now > max_distance_seconds/2                     # Half of expected max. distance
          Rails.logger.error "There are older partitions in table EVENT_LOGS with high value = #{compare_time} which will soon conflict with oldest possible high value of first non-interval partition"
        end
        if Time.now - min_time > max_distance_seconds                           # update of high_value of first non-interval partition should happen
          log_partitions
          # Check if more than one range partition exists
          if Database.select_one("SELECT COUNT(*) FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' AND Interval = 'NO'") > 1
            Rails.logger.info "There are more than one range partitions for table EVENT_LOGS with interval='NO'! Try to drop the first one"
            partition = Database.select_first_row("SELECT Partition_Name, Partition_Position, High_Value FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' AND Partition_Position = 1")
            EventLog.check_and_drop_partition(partition.partition_name, 'Housekeeping.check_partition_interval_internal')
          else
            current_interval = EventLog.current_interval_seconds
            Rails.logger.debug "Current partition interval is #{current_interval} seconds"
            # create dummy record with following rollback to enforce creation of interval partition
            split_partition_force_create_time1 = compare_time - (current_interval) -2   # smaller than expected high_value with 1 second rounding failure
            split_partition_force_create_time2 = split_partition_force_create_time1 - (current_interval)
            Rails.logger.debug "Create two empty partitions whith created_at=#{split_partition_force_create_time2} and #{split_partition_force_create_time1}"
            ActiveRecord::Base.transaction do
              [split_partition_force_create_time1, split_partition_force_create_time2].each do |created_at|
                Database.execute "INSERT INTO Event_Logs(ID, Created_At, Table_Id, Operation, DBUser, Payload) VALUES (Event_Logs_Seq.NextVal, TO_DATE(:created_at, 'YYYY-MM-DD HH24:MI:SS'), 5, 'I', 'hugo', 'hugo')",
                                 created_at: created_at.strftime('%Y-%m-%d %H:%M:%S')  # Don't use Time directly as bind variable because of timezone drift
              end
              raise ActiveRecord::Rollback
            end
            part2 =  Database.select_first_row "SELECT Partition_Name, High_Value FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' AND Partition_Position = 2"
            part3 =  Database.select_first_row "SELECT Partition_Name, High_Value FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' AND Partition_Position = 3"
            Rails.logger.debug "Partition created at position 2 with partition_name=#{part2.partition_name} and high_value=#{part2.high_value}"
            Rails.logger.debug "Partition created at position 3 with partition_name=#{part3.partition_name} and high_value=#{part3.high_value}"
            raise "No second and third oldest partitions found for table Event_Logs" if part2.nil? || part3.nil?
            Database.execute "ALTER TABLE Event_Logs MERGE PARTITIONS #{part2.partition_name}, #{part3.partition_name}"
            Rails.logger.debug "Partition merged from #{part2.partition_name} and #{part3.partition_name} at position 2 is partition_name=#{part2.partition_name} and high_value=#{part2.high_value}"
            # Drop partition only if empty and without transactions
            EventLog.check_and_drop_partition(part1.partition_name, 'Housekeeping.check_partition_interval_internal')
          end
        end
      end
    end

  ensure
    @last_partition_interval_check_started = nil
  end

  private
  def log_partitions
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      if Trixx::Application.partitioning?
        Rails.logger.debug "Housekeeping.log_partitions: All currently existing partitions"
        Database.select_all("SELECT * FROM User_Tab_Partitions WHERE  Table_Name = 'EVENT_LOGS' ORDER BY Partition_Position").each do |p|
          Rails.logger.debug "Pos=#{p.partition_position} #{p.partition_name} Interval=#{p.interval} HighValue=#{p.high_value}"
        end
      end
    end
  end
end