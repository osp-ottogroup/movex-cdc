namespace :ci_preparation do
  desc "Prepare preconditions for running tests in CI pipeline"

  task :create_test_user do
    def exec(conn, sql)
      puts "Execute: #{sql}"
      stmt = conn.prepareStatement(sql)
      stmt.executeUpdate
      stmt.close
    end

    puts "Creating test user in Oracle database"

    conn = java.sql.DriverManager.getConnection("jdbc:oracle:thin:system/oracle@localhost:1521/ORCLPDB1")

    exec(conn, "CREATE USER trixx IDENTIFIED BY \"trixx\" DEFAULT TABLESPACE USERS")
  end
end