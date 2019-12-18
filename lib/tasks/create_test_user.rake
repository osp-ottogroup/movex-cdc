namespace :ci_preparation do
  desc "Prepare preconditions for running tests in CI pipeline"

  task :create_test_user do

    def exec(conn, sql)
      puts "Execute: #{sql}"
      stmt = conn.prepareStatement(sql)
      stmt.executeUpdate
    ensure
      stmt.close rescue nil
    end

    def select_single(conn, sql)
      stmt = conn.prepareStatement(sql);
      resultSet = stmt.executeQuery(sql);
      resultSet.next
      result = resultSet.getInt(1)
      result
    ensure
      resultSet.close rescue nil
      stmt.close rescue nil
    end

    def ensure_user_existence(conn, username, password)
      puts "Check existence of user '#{username}'"
      exec(conn, "CREATE USER #{username} IDENTIFIED BY \"#{password}\" DEFAULT TABLESPACE USERS")  if select_single(conn, "SELECT COUNT(*) FROM All_Users WHERE UserName = UPPER('#{username}')") == 0
      exec(conn, "GRANT CONNECT TO #{username}")        if select_single(conn, "SELECT COUNT(*) FROM DBA_Role_Privs WHERE Grantee  = UPPER('#{username}') AND Granted_Role = 'CONNECT'") == 0
      exec(conn, "GRANT RESOURCE TO #{username}")       if select_single(conn, "SELECT COUNT(*) FROM DBA_Role_Privs WHERE Grantee  = UPPER('#{username}') AND Granted_Role = 'RESOURCE'") == 0

    end

    puts "Running ci_preparation:create_test_user for trixx_db_type = #{Trixx::Application.config.trixx_db_type }"
    if Trixx::Application.config.trixx_db_type == 'ORACLE'
      conn = java.sql.DriverManager.getConnection("jdbc:oracle:thin:system/oracle@#{Trixx::Application.config.trixx_db_url}")

      ensure_user_existence(conn, Trixx::Application.config.trixx_db_user,        Trixx::Application.config.trixx_db_password)          # Schema for TriXX data structure
      ensure_user_existence(conn, Trixx::Application.config.trixx_db_victim_user, Trixx::Application.config.trixx_db_victim_password)   # Schema for tables observed by trixx

      conn.close
    end

  end
end