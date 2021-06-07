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
        Database.execute "ALTER TABLE Event_Logs INITRANS #{expected_value}"
      end
    end
  end

  # Adjust interval
  def self.adjust_interval
    expected_interval = Trixx::Application.config.trixx_partition_interval
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      if Trixx::Application.partitioning?
        current_interval = Database.select_one "SELECT TO_NUMBER(SUBSTR(Interval, INSTR(Interval, '(')+1, INSTR(Interval, ',')-INSTR(Interval, '(')-1)) FROM User_Part_Tables WHERE Table_Name = 'EVENT_LOGS'"
        if current_interval.nil? || current_interval != expected_interval
          Rails.logger.info "EventLog.adjust_interval: Change partition interval from #{current_interval} to #{expected_interval} "
          Database.execute "ALTER TABLE Event_Logs SET INTERVAL(NUMTODSINTERVAL(#{expected_interval},'MINUTE'))"
        end
      end
    end
  end
end
