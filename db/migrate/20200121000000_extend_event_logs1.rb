class ExtendEventLogs1 < ActiveRecord::Migration[6.0]

  # create primary key constraint for test, otherwise loading fixtures will result in error
  def up
    if Rails.env.test?
      case Trixx::Application.config.trixx_db_type
      when 'ORACLE' then
        EventLog.connection.execute("ALTER TABLE Event_Logs ADD Constraint PK_Event_Logs PRIMARY KEY(ID)")
      end
    end
  end

  def down
    sql = "ALTER TABLE Event_Logs DROP Constraint PK_Event_Logs"
    EventLog.connection.execute(sql) if Rails.env.test?
  rescue Exception => e
    puts "Error: #{e.message}\nwhile executing:\n#{sql}"
  end

end
