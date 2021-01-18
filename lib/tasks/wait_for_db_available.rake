namespace :ci_preparation do
  desc "Wait for DB to become available in CI pipeline"

  task :wait_for_db_available, [:max_wait_minutes] do |_, args|
    puts "Running ci_preparation:wait_for_db_available for trixx_db_type = #{Trixx::Application.config.trixx_db_type }"
    max_wait_minutes = args[:max_wait_minutes].to_i
    raise "Parameter wait time in minutes expected" if args.count == 0 || max_wait_minutes == 0
    puts "Waiting max. #{max_wait_minutes} minutes for database to become available"
    start_time = Time.now

    if Trixx::Application.config.trixx_db_type == 'ORACLE'
      exception_text = nil
      loop do
        raise "DB not available after waiting #{max_wait_minutes} minutes! Aborting!\nReason: #{exception_text}\n" if Time.now > start_time + max_wait_minutes.minutes

        begin
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

          stmt = conn.prepareStatement("SELECT 1 FROM DUAL");
          resultSet = stmt.executeQuery;
          resultSet.next
          result = resultSet.getInt(1)
          break                                                                 # finished successful
        rescue Exception=> e
          exception_text = "#{e.class}: #{e.message}"
          print '.'
          sleep 1                                                               # Wait and try again
        ensure
          resultSet&.close
          stmt&.close
          conn&.close
        end
      end
      puts "\n#{Time.now}: DB is available now"
    end
  end
end