class HousekeepingFinalErrors

  @@instance = nil
  def self.get_instance
    @@instance = HousekeepingFinalErrors.new if @@instance.nil?
    @@instance
  end

  def do_housekeeping
    if @last_housekeeping_started.nil?
      Rails.logger.debug('HousekeepingFinalErrors.do_housekeeping'){ "Start housekeeping" }
      do_housekeeping_internal
      true                                                                      # signal state for test run only
    else
      Rails.logger.error('HousekeepingFinalErrors.do_housekeeping'){ "Last run started at #{@last_housekeeping_started} not yet finished!" }
      false                                                                     # signal state for test run only
    end
  end


  private
  def initialize                                                                # get singleton by get_instance only
    @last_housekeeping_started = nil                                            # semaphore to prevent multiple execution
  end

  def do_housekeeping_internal
    @last_housekeeping_started = Time.now

    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      if MovexCdc::Application.partitioning?
        # check all partitions for deletion if older than limit
        Database.select_all("\
          SELECT Partition_Name, High_Value, Partition_Position
          FROM   User_Tab_Partitions
          WHERE  Table_Name = 'EVENT_LOG_FINAL_ERRORS'
          AND Partition_Position > 1 /* Check all partitions without the first one (no interval) */
        "
        ).each do |part|
          # Get content of LONG datatype as real Time object
          high_value = Database.select_one "SELECT TO_DATE(:high_value, '\"TIMESTAMP'' \"YYYY-MM-DD HH24:MI:SS\"''\"') FROM DUAL", { high_value: part['high_value']}
          to_remove = Database.select_one "SELECT CASE WHEN TO_DATE(:high_value, '\"TIMESTAMP'' \"YYYY-MM-DD HH24:MI:SS\"''\"') < SYSDATE - :keep_hours / 24 THEN 1 ELSE 0 END FROM DUAL",
                                          { high_value: part['high_value'], keep_hours: MovexCdc::Application.config.final_errors_keep_hours}
          if to_remove == 1
            Rails.logger.info('HousekeepingFinalErrors.do_housekeeping_internal'){ "Check partition #{part['partition_name']} with high value #{part['high_value']} of table EVENT_LOG_FINAL_ERRORS for drop" }

            pending_transactions = Database.select_one("\
              SELECT COUNT(*)
              FROM   gv$Lock l
              JOIN   User_Objects o ON o.Object_ID = l.ID1
              WHERE  o.Object_Name    = 'EVENT_LOG_FINAL_ERRORS'
              AND    o.SubObject_Name = :partition_name
              ", partition_name: part['partition_name']
                )
            if pending_transactions > 0
              Rails.logger.info('HousekeepingFinalErrors.do_housekeeping_internal'){ "Drop partition #{part['partition_name']} with high value #{part['high_value']} not possible because there are #{pending_transactions} pending transactions" }
            else
              Rails.logger.info('HousekeepingFinalErrors.do_housekeeping_internal'){ "Execute drop partition #{part['partition_name']} with high value #{part['high_value']}" }
              Database.execute "ALTER TABLE Event_Log_Final_Errors DROP PARTITION #{part['partition_name']}"
              Rails.logger.info('HousekeepingFinalErrors.do_housekeeping_internal'){ "Successful dropped partition #{part['partition_name']} with high value #{part['high_value']}" }
            end
          end
        end
      else
        # Delete single records from table
        deleted = nil                                                           # declare variable outside begin/end
        begin
          ActiveRecord::Base.transaction do
            deleted = Database.execute "DELETE FROM Event_Log_Final_Errors
                                        WHERE  Error_Time < SYSDATE - #{MovexCdc::Application.config.final_errors_keep_hours} / 24
                                        AND    RowNum <= 1000000 /* limit transaction size to  */
                                       "
            Rails.logger.debug('HousekeepingFinalErrors.do_housekeeping_internal'){ "#{deleted} records deleted from Event_Log_Final_Errors" }
          end
        end while deleted > 0                                                   # Repeat until all too old records are deleted

      end
    when 'SQLITE' then
      ActiveRecord::Base.transaction do
        deleted = Database.execute "DELETE FROM Event_Log_Final_Errors WHERE Error_Time < DATE('now', '-#{MovexCdc::Application.config.final_errors_keep_hours} hours')"
        Rails.logger.debug('HousekeepingFinalErrors.do_housekeeping_internal'){ "#{deleted} records deleted from Event_Log_Final_Errors" }
      end
    end
  ensure
    @last_housekeeping_started = nil
  end


end