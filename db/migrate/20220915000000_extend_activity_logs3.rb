class ExtendActivityLogs3 < ActiveRecord::Migration[6.0]

  # Change column type from VARCHAR2(1000) to CLOB
  def up
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      ActivityLog.connection.execute("\
      DECLARE
        Dummy NUMBER;
      BEGIN
        SELECT COUNT(*) INTO Dummy FROM User_Tab_Columns
        WHERE  Table_Name  = 'ACTIVITY_LOGS'
        AND    Column_Name = 'ACTION'
        AND    Data_Type   = 'VARCHAR2'
        ;
        IF Dummy > 0 THEN
          EXECUTE IMMEDIATE 'ALTER TABLE Activity_Logs ADD (Action_New CLOB)';
          EXECUTE IMMEDIATE 'UPDATE Activity_Logs SET Action_New = Action';
          EXECUTE IMMEDIATE 'ALTER TABLE Activity_Logs DROP COLUMN Action';
          EXECUTE IMMEDIATE 'ALTER TABLE Activity_Logs RENAME COLUMN Action_New TO Action';
        END IF;
      END;
      ")
    end
  end

end

