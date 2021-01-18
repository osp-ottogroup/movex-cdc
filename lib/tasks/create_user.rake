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
      exec(conn, "GRANT SELECT ON gv_$Lock TO #{username}")
      exec(conn, "GRANT SELECT ON v_$Database TO #{username}")
      exec(conn, "GRANT SELECT ON v_$Instance TO #{username}")
      exec(conn, "GRANT SELECT ON v_$Session TO #{username}")
    end

    puts "Running ci_preparation:create_user for trixx_db_type = #{Trixx::Application.config.trixx_db_type }"
    if Trixx::Application.config.trixx_db_type == 'ORACLE'
      raise "Value for TRIXX_DB_SYS_PASSWORD required to create users" if !Trixx::Application.config.respond_to?(:trixx_db_sys_password)
      properties = java.util.Properties.new
      properties.put("user", 'sys')
      properties.put("password", Trixx::Application.config.trixx_db_sys_password)
      properties.put("internal_logon", "SYSDBA")
      url = "jdbc:oracle:thin:@#{Trixx::Application.config.trixx_db_url}"
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

      ensure_user_existence(conn, Trixx::Application.config.trixx_db_user,        Trixx::Application.config.trixx_db_password)          # Schema for TriXX data structure
      if Rails.env.test?
        ensure_user_existence(conn, Trixx::Application.config.trixx_db_victim_user, Trixx::Application.config.trixx_db_victim_password)   # Schema for tables observed by trixx
      end

      conn.close
    end

  end
end