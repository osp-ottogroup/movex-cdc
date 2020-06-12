class CreateAllowedDbTables < ActiveRecord::Migration[6.0]
  def up
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      EventLog.connection.execute "\
        CREATE OR REPLACE View Allowed_DB_Tables AS
        SELECT Owner, Owner Grantee, Table_Name FROM DBA_Tables /* Own schema has tables */
        UNION
        /* Explicite table grants for user */
        SELECT Owner, Grantee, Table_Name
        FROM   DBA_TAB_PRIVS
        WHERE  Privilege = 'SELECT'
        AND    Type = 'TABLE'
        UNION
        /* All schemas with tables if user has SELECT ANY TABLE */
        SELECT t.Owner, p.Grantee, t.Table_Name
        FROM   DBA_Tables t
        CROSS JOIN (SELECT Grantee FROM DBA_Sys_Privs WHERE Privilege = 'SELECT ANY TABLE') p
        "
    else
      ActiveRecord::Base.connection.execute "CREATE VIEW Allowed_DB_Tables AS SELECT 'main' Owner, 'main' Grantee, Name Table_Name FROM SQLite_Master"
    end
  end

  def down
    ActiveRecord::Base.connection.execute "DROP VIEW Allowed_DB_Tables"
  end
end




