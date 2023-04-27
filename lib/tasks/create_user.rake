namespace :ci_preparation do
  desc "Prepare preconditions for running tests in CI pipeline"

  task :create_user do

    def exec(conn, sql)
      puts "Execute: #{sql}"
      stmt = conn.prepareStatement(sql)
      stmt.executeUpdate
    ensure
      stmt.close rescue nil
    end

    def select_single(conn, sql)
      # puts "Execute: #{sql}"
      stmt = conn.prepareStatement(sql);
      resultSet = stmt.executeQuery;
      resultSet.next
      result = resultSet.getInt(1)
      result
    ensure
      resultSet.close rescue nil
      stmt.close rescue nil
    end

    def ensure_user_existence(conn, username, password)
      puts "Check existence and grants of user '#{username}'"
      tablespace = 'USERS'                                                      # Default / first choice
      tablespace = 'DATA'   if select_single(conn, "SELECT COUNT(*) FROM DBA_Tablespaces WHERE Tablespace_Name = '#{tablespace}'") == 0
      tablespace = 'TOOLS'  if select_single(conn, "SELECT COUNT(*) FROM DBA_Tablespaces WHERE Tablespace_Name = '#{tablespace}'") == 0
      tablespace = 'SYSAUX' if select_single(conn, "SELECT COUNT(*) FROM DBA_Tablespaces WHERE Tablespace_Name = '#{tablespace}'") == 0
      raise "No suitable tablespace found for users" if select_single(conn, "SELECT COUNT(*) FROM DBA_Tablespaces WHERE Tablespace_Name = '#{tablespace}'") == 0

      if select_single(conn, "SELECT COUNT(*) FROM All_Users WHERE UserName = UPPER('#{username}')") == 0
        exec(conn, "CREATE USER #{username} IDENTIFIED BY \"#{password}\" DEFAULT TABLESPACE #{tablespace}")
        exec(conn, "ALTER USER #{username} QUOTA UNLIMITED ON #{tablespace}")
      else
        puts "User #{username} already exists"
      end
      exec(conn, "GRANT CONNECT TO #{username}")                if select_single(conn, "SELECT COUNT(*) FROM DBA_Role_Privs WHERE Grantee  = UPPER('#{username}') AND Granted_Role = 'CONNECT'")                == 0
      exec(conn, "GRANT RESOURCE TO #{username}")               if select_single(conn, "SELECT COUNT(*) FROM DBA_Role_Privs WHERE Grantee  = UPPER('#{username}') AND Granted_Role = 'RESOURCE'")               == 0
      exec(conn, "GRANT CREATE ANY TRIGGER TO #{username}")     if select_single(conn, "SELECT COUNT(*) FROM DBA_Sys_Privs  WHERE Grantee  = UPPER('#{username}') AND Privilege    = 'CREATE ANY TRIGGER'")     == 0
      exec(conn, "GRANT CREATE VIEW TO #{username}")            if select_single(conn, "SELECT COUNT(*) FROM DBA_Sys_Privs  WHERE Grantee  = UPPER('#{username}') AND Privilege    = 'CREATE VIEW'")  == 0
      exec(conn, "GRANT SELECT ON DBA_Constraints TO #{username}")
      exec(conn, "GRANT SELECT ON DBA_Cons_Columns TO #{username}")
      exec(conn, "GRANT SELECT ON DBA_Role_Privs TO #{username}")
      exec(conn, "GRANT SELECT ON DBA_Sys_Privs TO #{username}")
      exec(conn, "GRANT SELECT ON DBA_Tables TO #{username}")
      exec(conn, "GRANT SELECT ON DBA_Tab_Columns TO #{username}")
      exec(conn, "GRANT SELECT ON DBA_Tab_Privs TO #{username}")
      begin
        exec(conn, "GRANT SELECT ON gv_$Lock TO #{username}")
      rescue Exception => e
        puts "GRANT SELECT ON gv_$Lock TO #{username} failed with #{e.message}"
        puts "Trying gv$Lock instead"
        exec(conn, "GRANT SELECT ON gv$Lock TO #{username}")
      end
      begin
        exec(conn, "GRANT SELECT ON v_$Database TO #{username}")
      rescue Exception => e
        puts "GRANT SELECT ON v_$Database TO #{username} failed with #{e.message}"
        puts "Trying v$Database instead"
        exec(conn, "GRANT SELECT ON v$Database TO #{username}")
      end

      begin
        exec(conn, "GRANT SELECT ON v_$Instance TO #{username}")
      rescue Exception => e
        puts "GRANT SELECT ON v_$Instance TO #{username} failed with #{e.message}"
        puts "Trying v$Instance instead"
        exec(conn, "GRANT SELECT ON v$Instance TO #{username}")
      end
      begin
        exec(conn, "GRANT SELECT ON v_$Session TO #{username}")
      rescue Exception => e
        puts "GRANT SELECT ON v_$Session TO #{username} failed with #{e.message}"
        puts "Trying v$Session instead"
        exec(conn, "GRANT SELECT ON v$Session TO #{username}")
      end

      # For test-users to fix slow access on All_Synonyms
      exec(conn, "CREATE OR REPLACE VIEW #{username}.Dummy AS SELECT null Owner, null table_owner, null table_name, null Synonym_name FROM DUAL WHERE 1=2")
      exec(conn, "GRANT CREATE SYNONYM TO #{username}")
      exec(conn, "CREATE OR REPLACE SYNONYM #{username}.All_Synonyms FOR #{username}.Dummy")
    end

    puts "Running ci_preparation:create_user for db_type = #{MovexCdc::Application.config.db_type }"
    if MovexCdc::Application.config.db_type == 'ORACLE'
      raise "Value for DB_SYS_PASSWORD required to create users" if !MovexCdc::Application.config.respond_to?(:db_sys_password)

      db_sys_user = if MovexCdc::Application.config.respond_to?(:db_sys_user)
                      MovexCdc::Application.config.db_sys_user
                    else 'sys'
                    end
      properties = java.util.Properties.new
      properties.put("user", db_sys_user)
      properties.put("password", MovexCdc::Application.config.db_sys_password)
      properties.put("internal_logon", "SYSDBA") if db_sys_user == 'sys'
      url = "jdbc:oracle:thin:@#{MovexCdc::Application.config.db_url}"
      begin
        conn = java.sql.DriverManager.getConnection(url, properties)
      rescue
        # bypass DriverManager to work in cases where ojdbc*.jar
        # is added to the load path at runtime and not on the
        # system classpath
        # ORACLE_DRIVER is declared in jdbc_connection.rb of oracle_enhanced-adapter like:
        # ORACLE_DRIVER = Java::oracle.jdbc.OracleDriver.new
        # java.sql.DriverManager.registerDriver ORACLE_DRIVER
        conn = ORACLE_DRIVER.connect(url, properties)
      end

      ensure_user_existence(conn, MovexCdc::Application.config.db_user, MovexCdc::Application.config.db_password)          # Schema for MOVEX CDC data structure
      if Rails.env.test?
        ensure_user_existence(conn, MovexCdc::Application.config.db_victim_user, MovexCdc::Application.config.db_victim_password)   # Schema for tables observed by MOVEX CDC
      end

      conn.close
    end

  end
end