namespace :ci_preparation do
  desc "Disable parallel query to ensure performance with Docker container and less CPU ressources.
Access to dictionary views has massively slowed down in PDB environments while using PQ.
  "

  task :speedup_oracle_dictionary_calls do

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

    puts "Running ci_preparation:speedup_oracle_dictionary_calls for db_type = #{MovexCdc::Application.config.db_type }"
    if MovexCdc::Application.config.db_type == 'ORACLE'
      raise "Value for DB_SYS_PASSWORD required to create users" if !MovexCdc::Application.config.respond_to?(:db_sys_password)
      properties = java.util.Properties.new
      properties.put("user", 'sys')
      properties.put("password", MovexCdc::Application.config.db_sys_password)
      properties.put("internal_logon", "SYSDBA")
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

      db_version_gt_12_1 = select_single conn, "SELECT CASE WHEN Version < '12.2' THEN 0 ELSE 1 END FROM v$Instance"
      if db_version_gt_12_1 == 1
        # Speed up execution in smaller test DBs
        # in 12.1: ORA-65040: operation not allowed from within a pluggable database
        #exec conn, "ALTER SYSTEM SET parallel_max_servers=0 SCOPE=BOTH"
      end

      # exclude "X$COMVW$" from execution plan
      # see also: Dictionary Queries Run Slowly in 12C Pluggable Databases (Doc ID 2033658.1)
      # https://support.oracle.com/epmos/faces/DocumentDisplay?_afrLoop=471348295695682&parent=EXTERNAL_SEARCH&sourceId=PROBLEM&id=2033658.1&_afrWindowMode=0&_adf.ctrl-state=dywy3nphu_4

      db_version_lt_12 = select_single conn, "SELECT CASE WHEN Version < '12' THEN 1 ELSE 0 END FROM v$Instance"
      if db_version_lt_12 == 0
        exec conn, 'ALTER SYSTEM SET "_common_data_view_enabled"=false SCOPE=BOTH'
      end

      conn.close
    end

  end
end