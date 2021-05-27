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

  # Ensure distance between MIN and current partition remains valid
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

    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      # check all partitions for deletion except the youngest one
      Database.select_all("\
        WITH Partitions AS (SELECT Partition_Name, High_Value, Partition_Position
                            FROM   User_Tab_Partitions
                            WHERE  Table_Name = 'EVENT_LOGS'
                            AND Partition_Name != 'MIN'
                           )
        SELECT Partition_Name, High_Value
        FROM   Partitions
        WHERE  Partition_Position != (SELECT MAX(Partition_Position) FROM Partitions) /* do not check the youngest partition for deletion */
        "
      ).each do |part|
        Rails.logger.info "Housekeeping: Check partition #{part['partition_name']} with high value #{part['high_value']} for deletion"
        pending_transactions = Database.select_one("\
          SELECT COUNT(*)
          FROM   gv$Lock l
          JOIN   User_Objects o ON o.Object_ID = l.ID1
          WHERE  o.Object_Name    = 'EVENT_LOGS'
          AND    o.SubObject_Name = :partition_name
          ", partition_name: part['partition_name']
        )
        if pending_transactions > 0
          Rails.logger.info "Housekeeping: Drop partition #{part['partition_name']} with high value #{part['high_value']} not possible because there are #{pending_transactions} pending transactions"
        else
          existing_records = Database.select_one "SELECT COUNT(*) FROM Event_Logs PARTITION (#{part['partition_name']})"
          if existing_records > 0
            Rails.logger.info "Housekeeping: Drop partition #{part['partition_name']} with high value #{part['high_value']} not possible because there are #{existing_records} records remaining"
          else
            Rails.logger.info "Housekeeping: Execute drop partition #{part['partition_name']} with high value #{part['high_value']}"
            Database.execute "ALTER TABLE Event_Logs DROP PARTITION #{part['partition_name']}"
            Rails.logger.info "Housekeeping: Successful dropped partition #{part['partition_name']} with high value #{part['high_value']}"
          end
        end
      end
    end

  ensure
    @last_housekeeping_started = nil
  end


  # check if high value of MIN partition must be lifted up because between MIN and last partition only 1024*1024-1 possible partitions are supported by Oracle
  # also check if expected interval for partitions has changed
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

        max_distance_minutes = (1024*1024-1) * Trixx::Application.config.trixx_partition_interval / 4 # 1/4 of allowed number of possible partitions
        min_time =  get_time_from_high_value.call(Database.select_one "SELECT High_Value FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' AND Partition_Name = 'MIN'")
        compare_time = Time.now
        Database.select_all("SELECT High_Value FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' AND Partition_Name != 'MIN'").each do |p|
          part_time = get_time_from_high_value.call(p.high_value)
          compare_time = part_time if part_time < compare_time                  # get oldest partition high value
        end
        if compare_time - Time.now > max_distance_minutes*60/2                  # Half of expected max. distance
          Rails.logger.error "There are older partitions in table EVENT_LOGS with high value = #{compare_time} which will soon conflict with oldest possible high value of MIN partition"
        end
        current_interval = Database.select_one "SELECT TO_NUMBER(SUBSTR(Interval, INSTR(Interval, '(')+1, INSTR(Interval, ',')-INSTR(Interval, '(')-1)) FROM User_Part_Tables WHERE Table_Name = 'EVENT_LOGS'"
        if Time.now - min_time > max_distance_minutes*60 || Trixx::Application.config.trixx_partition_interval != current_interval # update of high_value of MIN partition should happen
          new_min_time = compare_time - Trixx::Application.config.trixx_partition_interval*60*20   # set high value to 1/4 of possible distance to now
          if new_min_time < min_time
            Rails.logger.error "Unable to enlarge high value of MIN partition because suggested new high_value (#{new_min_time}) is older than current (#{min_time})"
            new_min_time = min_time                                             # keep the old high value and execute change nethertheless because interval may have changed
          end
          Rails.logger.info "Changing partitioned table EVENT_LOGS to interval #{Trixx::Application.config.trixx_partition_interval} minutes and high_value of MIN partition to #{new_min_time}"
          Database.execute "ALTER TABLE Event_Logs MODIFY PARTITION BY RANGE (Created_At) INTERVAL( NUMTODSINTERVAL(#{Trixx::Application.config.trixx_partition_interval},'MINUTE'))
                            ( PARTITION MIN VALUES LESS THAN (TO_DATE(' #{new_min_time.strftime('%Y-%m-%d %H:%M:%S')}', 'SYYYY-MM-DD HH24:MI:SS', 'NLS_CALENDAR=GREGORIAN')) )
                            ONLINE"
        end
      end
    end

  ensure
    @last_partition_interval_check_started = nil
  end

end