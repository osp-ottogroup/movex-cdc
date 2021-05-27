namespace :ci_preparation do
  desc "Disable parallel query to ensure performance with Docker container and less CPU ressources.
Access to dictionary views has massively slowed down in PDB environments while using PQ.
  "

  task :disable_parallel_query do

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
      resultSet = stmt.executeQuery(sql);
      resultSet.next
      result = resultSet.getInt(1)
      result
    ensure
      resultSet.close rescue nil
      stmt.close rescue nil
    end

    puts "Running ci_preparation:disable_parallel_query for trixx_db_type = #{Trixx::Application.config.trixx_db_type }"
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

      db_version_gt_12_1 = select_single conn, "SELECT CASE WHEN Version > '12.1' THEN 1 ELSE 0 END FROM v$Instance"
      if db_version_gt_12_1
        # Speed up execution in smaller test DBs
        exec conn, "ALTER SYSTEM SET parallel_max_servers=0 SCOPE=BOTH"
      end

      conn.close
    end

  end
end