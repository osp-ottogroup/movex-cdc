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
      true
    else
      Rails.logger.error "Housekeeping.do_housekeeping: Last run started at #{@last_housekeeping_started} not yet finished!"
      false
    end
  end


  private
  def initialize                                                                # get singleton by get_instance only
    @last_housekeeping_started = nil                                            # semaphore to prevent multiple execution
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
        WHERE  Partition_Position != (SELECT MAX(Partition_Position) FROM Partitions)
        "
      ).each do |part|
        part_high_value_ts = Time.parse(part['high_value'])
        oldest_high_value = Database.select_one "SELECT SYSDATE - 1/24 FROM DUAL" # Use time from DB because of possibe different time zone compared to client
        if part_high_value_ts < oldest_high_value                               # Check partitions only with high_value older than x hours
          Rails.logger.info "Housekeeping: Check partition #{part['partition_name']} with high value #{part['high_value']} for deletion"
          pending_transactions = Database.select_one("\
            SELECT COUNT(*)
            FROM   gv$Lock l
            JOIN   All_Objects o ON o.Object_ID = l.ID1
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
    end

  ensure
    @last_housekeeping_started = nil
  end


end