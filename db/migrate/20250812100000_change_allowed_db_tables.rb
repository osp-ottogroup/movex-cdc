class ChangeAllowedDbTables < ActiveRecord::Migration[6.0]
  def up
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      EventLog.connection.execute "\
        CREATE OR REPLACE View Allowed_DB_Tables AS
        SELECT Owner, Grantee, Table_Name
        FROM   (
                /* Own schema has tables */
                SELECT Owner, Owner Grantee, Table_Name FROM DBA_Tables
                UNION
                /* Explicit table grants for user */
                SELECT Owner, Grantee, Table_Name
                FROM   DBA_TAB_PRIVS
                WHERE  Privilege IN ('SELECT', 'READ')
                AND    Type      = 'TABLE'
                UNION
                /* Implicit table grants for users's roles */
                SELECT tp.Owner, rp.Grantee, tp.Table_Name
                FROM   DBA_Tab_Privs tp
                JOIN   (SELECT p.Granted_Role, CONNECT_BY_ROOT p.GRANTEE Grantee
                        FROM   DBA_Role_Privs p
                        JOIN   DBA_Roles r ON r.Role = p.Granted_Role
                        WHERE  r.Authentication_Type = 'NONE' /* Accept roles if they can be activated without authentication */
                        OR     Default_Role = 'YES'           /* Accept roles only if fix assignment to user exists */
                        CONNECT BY PRIOR p.Granted_Role = p.Grantee
                       ) rp ON rp.Granted_Role = tp.Grantee
                WHERE  tp.Privilege IN ('SELECT', 'READ')
                AND    tp.Type      = 'TABLE'
                AND    tp.Owner NOT IN (SELECT UserName FROM All_Users WHERE Oracle_Maintained = 'Y') /* Don't show SYS, SYSTEM etc. */
                UNION
                /* All Tables with public select access */
                SELECT tp.Owner, u.UserName Grantee, tp.Table_Name
                FROM   DBA_Tab_Privs tp
                CROSS JOIN All_Users u
                WHERE  tp.Grantee          = 'PUBLIC'
                AND    tp.Privilege        IN ('SELECT', 'READ')
                AND    tp.Type      = 'TABLE'
                AND    tp.Owner NOT IN (SELECT UserName FROM All_Users WHERE Oracle_Maintained = 'Y') /* Don't show SYS, SYSTEM etc. */
                UNION
                /* All schemas with tables if user has SELECT ANY TABLE */
                SELECT t.Owner, p.Grantee, t.Table_Name
                FROM   DBA_Tables t
                CROSS JOIN (SELECT Grantee FROM DBA_Sys_Privs WHERE Privilege = 'SELECT ANY TABLE') p
               )
        WHERE  Table_Name NOT LIKE 'BIN$%'  /* exclude recycle bin */
        "
    else
      # Change is for Oracle only
    end
  end

  def down
    # Nothing to do here, as the view is created by the migration CreateAllowedDbTables
  end
end




