class EventLog < ApplicationRecord
  self.primary_key    = :id                                                     # table does not have real PK constraint
  self.sequence_name  = :event_logs_seq

  def self.adjust_max_simultaneous_transactions
    expected_value = MovexCdc::Application.config.max_simultaneous_transactions
    workaround_hint = ''                                                        # possible workaround hint at exception
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      assumed_simultaneous_user_tx = 20
      suggested_min_value = MovexCdc::Application.config.max_simultaneous_table_initializations + MovexCdc::Application.config.initial_worker_threads + assumed_simultaneous_user_tx
      if expected_value < suggested_min_value
        msg = "EventLog.adjust_max_simultaneous_transactions: Setting of #{expected_value} for config parameter MAX_SIMULTANEOUS_TRANSACTIONS should be increased to at least #{suggested_min_value}"
        msg << " because it is smaller than MAX_SIMULTANEOUS_TABLE_INITIALIZATIONS (#{MovexCdc::Application.config.max_simultaneous_table_initializations}) +"
        msg << " INITIAL_WORKER_THREADS (#{MovexCdc::Application.config.initial_worker_threads}) +"
        msg << " assumed number of simultaneous user transactions (#{assumed_simultaneous_user_tx})"
        Rails.logger.error("EventLog.adjust_simultaneous_transactions") { msg }
      end

      if MovexCdc::Application.partitioning?
        current_value =  Database.select_one "SELECT def_ini_trans from User_Part_Tables WHERE Table_Name ='EVENT_LOGS'"
        if current_value != expected_value
          workaround_hint = "MAX_SIMULTANEOUS_TRANSACTIONS = #{current_value}"
          Rails.logger.info('EventLog.adjust_max_simultaneous_transactions'){ "Change INI_TRANS of table EVENT_LOGS from #{current_value} to #{expected_value}" }
          Database.execute "ALTER SESSION SET DDL_LOCK_TIMEOUT=20"              # Retry for 20 seconds before raising ORA-00054 if table Event_Logs is busy
          Database.execute "ALTER TABLE Event_Logs MODIFY DEFAULT ATTRIBUTES INITRANS #{expected_value}"
        end
      else                                                                      # non-partitioned table
        current_value = Database.select_one "SELECT ini_trans from User_Tables WHERE Table_Name ='EVENT_LOGS'"
        if current_value != expected_value
          workaround_hint = "MAX_SIMULTANEOUS_TRANSACTIONS = #{current_value}"
          Rails.logger.info('EventLog.adjust_max_simultaneous_transactions'){ "Change INI_TRANS of table EVENT_LOGS from #{current_value} to #{expected_value}" }
          Database.execute "ALTER SESSION SET DDL_LOCK_TIMEOUT=20"              # Retry for 20 seconds before raising ORA-00054 if table Event_Logs is busy
          Database.execute "ALTER TABLE Event_Logs INITRANS #{expected_value}"
          begin
            Database.execute "ALTER TABLE Event_Logs MOVE#{" ONLINE" if Database.db_version >= '12.2'}", options: { no_exception_logging: true}
          rescue Exception => e
            if e.message['ORA-00439']                                           # feature not enabled: Online Index Build
              Rails.logger.debug('EventLog.adjust_max_simultaneous_transactions'){'ORA-00439 with ONLINE, retrying without ONLINE'}
              Database.execute "ALTER TABLE Event_Logs MOVE"
            else
              raise
            end
          end
        end

        # Additional check for index
        current_value = Database.select_one "SELECT ini_trans from User_Indexes WHERE Index_Name ='EVENT_LOGS_PK'"
        if current_value != expected_value
          workaround_hint = "MAX_SIMULTANEOUS_TRANSACTIONS = #{current_value} for index"
          Rails.logger.info('EventLog.adjust_max_simultaneous_transactions'){ "Change INI_TRANS of index EVENT_LOGS_PK from #{current_value} to #{expected_value}" }
          Database.execute "ALTER SESSION SET DDL_LOCK_TIMEOUT=20"              # Retry for 20 seconds before raising ORA-00054 if table Event_Logs is busy
          begin
            Database.execute "ALTER INDEX Event_Logs_PK REBUILD ONLINE INITRANS #{expected_value}", options: { no_exception_logging: true}
          rescue Exception => e
            if e.message['ORA-00439']                                           # feature not enabled: Online Index Build
              Rails.logger.debug('EventLog.adjust_max_simultaneous_transactions'){'ORA-00439 with ONLINE, retrying without ONLINE'}
              Database.execute "ALTER INDEX Event_Logs_PK REBUILD INITRANS #{expected_value}"
            else
              raise
            end
          end
        end
      end
    end
  rescue Exception=>e
    EventLog.log_resource_busy_error_helper(e, workaround_hint)
    raise
  end

  def self.current_interval_seconds
    interval = Database.select_one "SELECT TO_NUMBER(SUBSTR(Interval, INSTR(Interval, '(')+1, INSTR(Interval, ',')-INSTR(Interval, '(')-1)) *
                                                       CASE WHEN INSTR(Interval, 'MINUTE') > 0 THEN 60 ELSE 1 /* seconds */ END
                                                FROM   User_Part_Tables
                                                WHERE  Table_Name = 'EVENT_LOGS'"
    raise "Table EVENT_LOGS is not partitioned but should be for a DB supporting partitioning! Remove schema.rb and start again with an empty schema!" if interval.nil?
    interval
  end

  # Adjust interval
  def self.adjust_interval
    expected_interval = MovexCdc::Application.config.partition_interval
    workaround_hint = ''                                                        # possible workaround hint at exception
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      if MovexCdc::Application.partitioning?
        current_interval = current_interval_seconds
        if current_interval.nil? || current_interval != expected_interval
          workaround_hint = "PARTITION_INTERVAL = #{current_interval}"
          Rails.logger.info('EventLog.adjust_interval'){ "Change partition interval from #{current_interval} to #{expected_interval} seconds" }
          Database.execute "ALTER SESSION SET DDL_LOCK_TIMEOUT=20"              # Retry for 20 seconds before raising ORA-00054 if table Event_Logs is busy
          Database.execute "ALTER TABLE Event_Logs SET INTERVAL(NUMTODSINTERVAL(#{expected_interval},'SECOND'))"
        end
      end
    end
  rescue Exception=>e
    EventLog.log_resource_busy_error_helper(e, workaround_hint)
    raise
  end

  # called by health_check controller
  def self.health_check_status
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      if MovexCdc::Application.partitioning?
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
      else
        max_records_to_count = 50000                                            # Limit the count to have a prdictable runtime for SQL

        record_count = Database.select_one("SELECT COUNT(*) FROM Event_Logs WHERE RowNum <= :max_count", max_count: max_records_to_count)
        retval = { record_count: record_count}
        if record_count == max_records_to_count
          retval[:note] = "Only the first #{max_records_to_count} rows have been counted to limit runtime of counting SQL"
        end
        retval
      end
    when 'SQLITE' then
      { record_count: Database.select_one("SELECT COUNT(*) FROM Event_Logs")}
    end
  end

  # Drop the partition if it is empty and no transactions are pending
  # @param partition_name: Partition to process
  # @param called_by: Name of calling module
  # @param [TrueClass] lock_already_checked: signal if partition is already checked for pending transactions
  def self.check_and_drop_partition(partition_name, called_by, lock_already_checked: false)
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      # partition_position must be read again for each partition because it changes if a previous partition is dropped
      part = Database.select_first_row "SELECT Partition_Position, High_Value
                                        FROM   User_Tab_Partitions
                                        WHERE  Table_Name = 'EVENT_LOGS'
                                        AND    Partition_Name = :partition_name
                                       ", partition_name: partition_name
      if part.nil?
        Rails.logger.info('EventLog.check_and_drop_partition') { "Called by #{called_by}: Partition #{partition_name} does not exist no more, dropped by previous call of Housekeeping.do_housekeeping_internal" }
      else
        if self.partition_allowed_for_drop?(partition_name, part.partition_position, part.high_value, called_by, lock_already_checked: lock_already_checked)
          Rails.logger.info('EventLog.check_and_drop_partition') { "Called by #{called_by}: Execute drop partition #{partition_name} with high value #{part.high_value} at position = #{part.partition_position}" }
          Database.execute "ALTER TABLE Event_Logs DROP PARTITION #{partition_name}"
          Rails.logger.info('EventLog.check_and_drop_partition') { "Called by #{called_by}: Successful dropped partition #{partition_name} with high value #{part.high_value} at position = #{part.partition_position}" }
        end
      end
    end
  end

  # Is partition in a state that it can be dropped
  # @param [String] partition_name
  # @param [Integer] partition_position
  # @param [String] high_value
  # @param [String] called_by
  # @param [TrueClass] lock_already_checked signal if partition is already checked for pending transactions
  def self.partition_allowed_for_drop?(partition_name, partition_position, high_value, called_by, lock_already_checked: false)
    Rails.logger.debug('EventLog.partition_allowed_for_drop?') { "Called by #{called_by}: Check partition #{partition_name} with high value #{high_value} for deletion" }

    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      part_stat = Database.select_first_row("SELECT MAX(Partition_Position) max_partition_position, COUNT(*) Partition_Count
                                             FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS'")
      if part_stat.max_partition_position == partition_position
        msg = "Partition #{partition_name} with high value #{high_value} at position = #{partition_position} is the last partition of table EVENT_LOGS and should not be dropped"
        Rails.logger.error("EventLog.partition_allowed_for_drop?") { msg }
        self.error_log_partitions
        return false
      end

      if part_stat.partition_count < 3
        msg = "Partition #{partition_name} with high value #{high_value} at position = #{partition_position} is one of the last two partitions of table EVENT_LOGS and should not be dropped"
        Rails.logger.error("EventLog.partition_allowed_for_drop?") { msg }
        self.error_log_partitions
        return false
      end

      return false unless self.partition_empty?(partition_name, partition_position, high_value, called_by, lock_already_checked: lock_already_checked)

      if partition_position == 1                                                  # next partition must be empty because first partition is not scanned by workers
        next_part = Database.select_first_row "SELECT Partition_Name, Partition_Position, High_Value,
                                                      'TIMESTAMP'' '||TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS')||'''' High_Value_Compare
                                               FROM   User_Tab_Partitions
                                               WHERE  Table_Name = 'EVENT_LOGS'
                                               AND    Partition_Position = 2
                                              "
        if next_part.nil?
          Rails.logger.error('EventLog.partition_allowed_for_drop?') { "Partition #{partition_name} with high value #{high_value} at position = #{partition_position} cannot be dropped because it is the last partition!" }
          return false
        end
        unless self.partition_empty?(next_part.partition_name, next_part.partition_position, next_part.high_value, called_by)
          Rails.logger.warn('EventLog.partition_allowed_for_drop?') { "Partition #{partition_name} with high value #{high_value} at position = #{partition_position} cannot be dropped because next partition #{next_part.partition_name} with high_value #{next_part.high_value} at position #{next_part.partition_position} is not empty!" }
          return false
        end
        if next_part.high_value >= next_part.high_value_compare
          Rails.logger.error('EventLog.partition_allowed_for_drop?') { "Partition #{partition_name} with high value #{high_value} at position = #{partition_position} cannot be dropped because high value of next partition is not older than sysdate! Next partition #{next_part.partition_name}, high_value: #{next_part.high_value}, position #{next_part.partition_position}, compare high value: #{next_part.high_value_compare} !" }
          return false
        end
      end
    end

    true
  end

  # check if partition does not contain records or pending transactions
  # @param {String} partition_name
  # @param {Integer} partition_position
  # @param {String} high_value
  # @param {String} called_by
  # @param {TrueClass|FalseClass} lock_already_checked: signal if partition is already checked for pending transactions
  def self.partition_empty?(partition_name, partition_position, high_value, called_by, lock_already_checked: false)
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      unless lock_already_checked                                               # Check for pending transaction only if this wasn't already done by called_by
        pending_transactions = Database.select_one("\
              SELECT COUNT(*)
              FROM   gv$Lock l
              JOIN   User_Objects o ON o.Object_ID = l.ID1
              WHERE  o.Object_Name    = 'EVENT_LOGS'
              AND    o.SubObject_Name = :partition_name
              ", partition_name: partition_name
        )
        if pending_transactions > 0
          Rails.logger.info('EventLog.partition_empty?') { "Called by #{called_by}: Drop partition #{partition_name} with high value #{high_value} at position = #{partition_position} not possible because there are #{pending_transactions} pending transactions" }
          return false
        end
      end

      existing_records = Database.select_one "SELECT COUNT(*) FROM Event_Logs PARTITION (#{partition_name}) WHERE Rownum < 2"
      if existing_records > 0
        Rails.logger.info('EventLog.partition_empty?') { "Called by #{called_by}: Drop partition #{partition_name} with high value #{high_value} at position = #{partition_position} not possible because there are one or more records remaining" }
        return false
      end
    end

    true
  end

  # log current partitions of table on error conditions
  def self.error_log_partitions
    Rails.logger.error('EventLog.error_log_partitions') { "Current existing partitions are:" }
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      if MovexCdc::Application.partitioning?
        Database.select_all("SELECT Partition_Position, Partition_Name, High_Value, Interval FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS'").each do |p|
          Rails.logger.error('EventLog.error_log_partitions') { "Pos=#{p.partition_position}, name=#{p.partition_name}, high_value=#{p.high_value}, interval=#{p.interval}" }
        end
      end
    end
  end

  def self.log_resource_busy_error_helper(exception, workaround_hint)
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      if exception.message['ORA-00054']
        Rails.logger.warn('Event_log.log_resource_busy_error_helper') { '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!' }
        Rails.logger.warn('Event_log.log_resource_busy_error_helper') {  "Table EVENT_LOGS must not be locked by any other transactions during startup of MOVEX CDC to allow this transformation!" }
        Rails.logger.warn('Event_log.log_resource_busy_error_helper') {  "Possible workaround: set '#{workaround_hint}' in startup configuration to start without transformation on EVENT_LOGS." }
        Rails.logger.warn('Event_log.log_resource_busy_error_helper') {  "Restart the application at a later time with the adjusted configuration, if no transactions are active on the table then." }
        Rails.logger.warn('Event_log.log_resource_busy_error_helper') {  '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!' }
      end
    end
  end

end
