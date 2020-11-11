class HousekeepingFinalErrors

  @@instance = nil
  def self.get_instance
    @@instance = HousekeepingFinalErrors.new if @@instance.nil?
    @@instance
  end

  def do_housekeeping
    if @last_housekeeping_started.nil?
      Rails.logger.debug "HousekeepingFinalErrors.do_housekeeping: Start housekeeping"
      do_housekeeping_internal
      true                                                                      # signal state for test run only
    else
      Rails.logger.error "HousekeepingFinalErrors.do_housekeeping: Last run started at #{@last_housekeeping_started} not yet finished!"
      false                                                                     # signal state for test run only
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
      if Trixx::Application.partitioning?
        # check all partitions for deletion if older than limit
        Database.select_all("\
          SELECT Partition_Name, High_Value, Partition_Position
          FROM   User_Tab_Partitions
          WHERE  Table_Name = 'EVENT_LOG_FINAL_ERRORS'
          AND Partition_Name != 'MIN'
        "
        ).each do |part|
          # Get content of LONG datatype as real Time object
          high_value = Database.select_one "SELECT TO_DATE(:high_value, '\"TIMESTAMP'' \"YYYY-MM-DD HH24:MI:SS\"''\"') FROM DUAL", { high_value: part['high_value']}
          to_remove = Database.select_one "SELECT CASE WHEN TO_DATE(:high_value, '\"TIMESTAMP'' \"YYYY-MM-DD HH24:MI:SS\"''\"') < SYSDATE - :keep_hours / 24 THEN 1 ELSE 0 END FROM DUAL",
                                          { high_value: part['high_value'], keep_hours: Trixx::Application.config.trixx_final_errors_keep_hours}
          if to_remove == 1
            Rails.logger.info "HousekeepingFinalErrors: Check partition #{part['partition_name']} with high value #{part['high_value']} of table EVENT_LOG_FINAL_ERRORS for drop"

            pending_transactions = Database.select_one("\
              SELECT COUNT(*)
              FROM   gv$Lock l
              JOIN   User_Objects o ON o.Object_ID = l.ID1
              WHERE  o.Object_Name    = 'EVENT_LOG_FINAL_ERRORS'
              AND    o.SubObject_Name = :partition_name
              ", partition_name: part['partition_name']
                )
            if pending_transactions > 0
              Rails.logger.info "HousekeepingFinalObjects: Drop partition #{part['partition_name']} with high value #{part['high_value']} not possible because there are #{pending_transactions} pending transactions"
            else
              Rails.logger.info "HousekeepingFinalObjects: Execute drop partition #{part['partition_name']} with high value #{part['high_value']}"
              Database.execute "ALTER TABLE Event_Log_Final_Errors DROP PARTITION #{part['partition_name']}"
              Rails.logger.info "HousekeepingFinalObjects: Successful dropped partition #{part['partition_name']} with high value #{part['high_value']}"
            end
          end
        end
      else
        # Delete single records from table

      end
    when 'SQLITE' then
      Database.execute "DELETE FROM Event_Log_Final_Errors WHERE Error_Time < DATE('now', '-#{Trixx::Application.config.trixx_final_errors_keep_hours} hours')"
    end
  ensure
    @last_housekeeping_started = nil
  end


end