class EventLogFinalError < ApplicationRecord
  self.primary_key    = :id                                                     # table does not have real PK constraint
  self.sequence_name  = :event_log_final_error_seq                              # non-existing sequence, but needed for Rails

  # Count the number of records in table as quick as possible
  # @param [Integer] max_count The maximum number of records to count to return result quickly
  # @return [Integer] The number of records in the table <= max_count
  def self.final_error_count(max_count:)
    case MovexCdc::Application.config.db_type
     when 'ORACLE' then
       Database.select_one "SELECT COUNT(*) FROM #{MovexCdc::Application.config.db_user}.Event_Log_Final_Errors WHERE RowNum <= :max_rows", max_rows: max_count
     when 'SQLITE' then
       Database.select_one "SELECT COUNT(*) FROM #{MovexCdc::Application.config.db_user}.Event_Log_Final_Errors LIMIT :max_rows", max_rows: max_count
     end
  end

  # Get any error message from the table as quick as possible
  # @return [String] a random error message from the table or nil
  def self.an_error_message
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      Database.select_one "SELECT Error_Msg FROM #{MovexCdc::Application.config.db_user}.Event_Log_Final_Errors WHERE RowNum < 2"
    when 'SQLITE' then
      Database.select_one "SELECT Error_Msg FROM #{MovexCdc::Application.config.db_user}.Event_Log_Final_Errors LIMIT 1"
    end
  end

end
