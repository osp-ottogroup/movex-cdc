class EventLog < ApplicationRecord
  self.primary_key    = :id                                                     # table does not have real PK constraint
  self.sequence_name  = :event_logs_seq

  def self.adjust_max_simultaneous_transactions
    expected_value = Trixx::Application.config.trixx_max_simultaneous_transactions
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      current_value =  if Trixx::Application.partitioning?
                         Database.select_one "SELECT def_ini_trans from User_Part_Tables WHERE Table_Name ='EVENT_LOGS'"
                       else
                         Database.select_one "SELECT ini_trans from User_Tables WHERE Table_Name ='EVENT_LOGS'"
                       end
      if current_value != expected_value
        Rails.logger.info "Change INI_TRANS of table EVENT_LOGS from #{current_value} to #{expected_value}"
        Database.execute "ALTER SESSION SET DDL_LOCK_TIMEOUT=20"              # Retry for 20 seconds before raising ORA-00054 if table Event_Logs is busy
        Database.execute "ALTER TABLE Event_Logs INITRANS #{expected_value}"
      end
    end
  end

  def self.current_interval_seconds
    Database.select_one "SELECT TO_NUMBER(SUBSTR(Interval, INSTR(Interval, '(')+1, INSTR(Interval, ',')-INSTR(Interval, '(')-1)) *
                                                       CASE WHEN INSTR(Interval, 'MINUTE') > 0 THEN 60 ELSE 1 /* seconds */ END
                                                FROM   User_Part_Tables
                                                WHERE  Table_Name = 'EVENT_LOGS'"
  end

  # Adjust interval
  def self.adjust_interval
    expected_interval = Trixx::Application.config.trixx_partition_interval
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      if Trixx::Application.partitioning?
        current_interval = current_interval_seconds
        if current_interval.nil? || current_interval != expected_interval
          Rails.logger.info "EventLog.adjust_interval: Change partition interval from #{current_interval} to #{expected_interval} seconds "
          Database.execute "ALTER SESSION SET DDL_LOCK_TIMEOUT=20"              # Retry for 20 seconds before raising ORA-00054 if table Event_Logs is busy
          Database.execute "ALTER TABLE Event_Logs SET INTERVAL(NUMTODSINTERVAL(#{expected_interval},'SECOND'))"
        end
      end
    end
  end

  # called by health_check controller
  def self.health_check_status
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      if Trixx::Application.partitioning?
        partitions = Database.select_all "SELECT Partition_Name, High_Value
                                          FROM   User_Tab_Partitions
                                          WHERE  Table_Name = 'EVENT_LOGS'
                                          AND    Partition_Position > 1
                                          ORDER BY Partition_Position"
        min_high_value = 'X'
        max_high_value = ''
        partitions.each do |part|
          min_high_value = part.high_value if part.high_value < min_high_value
          max_high_value = part.high_value if part.high_value > max_high_value
        end
        retval = { used_partition_count: partitions.length }
        retval[:min_partition_high_value] = min_high_value if partitions.length > 0
        retval[:max_partition_high_value] = max_high_value if partitions.length > 0
        retval
      end
    when 'SQLITE' then
      { record_count: Database.select_one("SELECT COUNT(*) FROM Event_Logs")}
    end
  end

  # Drop the partition if it is empty and no transactions are pending
  def self.check_and_drop_partition(partition_name, partition_position, high_value, caller)
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      Rails.logger.info "#{caller}: Check partition #{partition_name} with high value #{high_value} for deletion"
      max_partition_position = Database.select_one("SELECT MAX(Partition_Position) FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS'")
      if max_partition_position == partition_position
        msg = "Partition #{partition_name} with high value #{high_value} at position = #{partition_position} is the last partition of table EVENT_LOGS and should not be dropped"
        Rails.logger.error msg
        Rails.logger.error "Current existing partitions are:"
        Database.select_all("SELECT Partition_Position, Partition_Name, High_Value, Interval FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS'").each do |part|
          Rails.logger.error "Pos=#{part.partition_position}, name=#{part.partition_name}, high_value=#{part.high_value}, interval=#{part.interval}"
        end
        raise msg
      end
      pending_transactions = Database.select_one("\
            SELECT COUNT(*)
            FROM   gv$Lock l
            JOIN   User_Objects o ON o.Object_ID = l.ID1
            WHERE  o.Object_Name    = 'EVENT_LOGS'
            AND    o.SubObject_Name = :partition_name
            ", partition_name: partition_name
      )
      if pending_transactions > 0
        Rails.logger.info "#{caller}: Drop partition #{partition_name} with high value #{high_value} not possible because there are #{pending_transactions} pending transactions"
      else
        existing_records = Database.select_one "SELECT COUNT(*) FROM Event_Logs PARTITION (#{partition_name})"
        if existing_records > 0
          Rails.logger.info "#{caller}: Drop partition #{partition_name} with high value #{high_value} not possible because there are #{existing_records} records remaining"
        else
          Rails.logger.info "#{caller}: Execute drop partition #{partition_name} with high value #{high_value}"
          Database.execute "ALTER TABLE Event_Logs DROP PARTITION #{partition_name}"
          Rails.logger.info "#{caller}: Successful dropped partition #{partition_name} with high value #{high_value}"
        end
      end
    end
  end

end
