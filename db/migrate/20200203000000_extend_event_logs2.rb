class ExtendEventLogs2 < ActiveRecord::Migration[6.0]

  # create primary key constraint for test, otherwise loading fixtures will result in error
  def up
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      EventLog.connection.execute("ALTER SEQUENCE Event_Logs_SEQ CACHE 100000")
    end
  end

end
