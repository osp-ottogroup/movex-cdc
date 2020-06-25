class CreateAllowedDbTables < ActiveRecord::Migration[6.0]
  def up
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      EventLog.connection.execute "\
        CREATE OR REPLACE View Allowed_DB_Tables AS
        /* Own schema has tables */
        SELECT Owner, Owner Grantee, Table_Name FROM DBA_Tables
        UNION
        /* Explicite table grants for user */
        SELECT Owner, Grantee, Table_Name
        FROM   DBA_TAB_PRIVS
        WHERE  Privilege = 'SELECT'
        AND    Type      = 'TABLE'
        UNION
        /* Implicite table grants for users's roles */
        SELECT tp.Owner, rp.Grantee, tp.Table_Name
        FROM   DBA_Tab_Privs tp
        JOIN   (SELECT Granted_Role, CONNECT_BY_ROOT GRANTEE Grantee
                FROM DBA_Role_Privs
                CONNECT BY PRIOR Granted_Role = Grantee
               ) rp ON rp.Granted_Role = tp.Grantee
        WHERE  tp.Privilege = 'SELECT'
        AND    tp.Type      = 'TABLE'
        AND    tp.Owner NOT IN (SELECT UserName FROM All_Users WHERE Oracle_Maintained = 'Y') /* Don't show SYS, SYSTEM etc. */
        UNION
        /* All Tables with public select access */
        SELECT tp.Owner, u.UserName Grantee, tp.Table_Name
        FROM   DBA_Tab_Privs tp
        CROSS JOIN All_Users u
        WHERE  tp.Grantee          = 'PUBLIC'
        AND    tp.Privilege        = 'SELECT'
        AND    tp.Type             = 'TABLE'
        AND    tp.Owner NOT IN (SELECT UserName FROM All_Users WHERE Oracle_Maintained = 'Y') /* Don't show SYS, SYSTEM etc. */
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




