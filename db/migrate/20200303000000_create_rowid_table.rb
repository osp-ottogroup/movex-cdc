class CreateRowidTable < ActiveRecord::Migration[6.0]

  # create primary key constraint for test, otherwise loading fixtures will result in error
  def up
    case Trixx::Application.config.db_type
    when 'ORACLE' then
      EventLog.connection.execute("CREATE OR REPLACE TYPE RowID_Table AS TABLE OF VARCHAR2(18)")  # 18 is maximum length of Oracle RowID in char notation
    end
  end

  def down
    case Trixx::Application.config.db_type
    when 'ORACLE' then
      begin
        sql = "DROP TYPE RowID_Table"
        EventLog.connection.execute(sql)
      rescue Exception => e
        puts "Error: #{e.message}\nwhile executing:\n#{sql}"
      end
    end
  end

end
