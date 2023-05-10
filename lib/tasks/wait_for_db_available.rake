
# This task is used in the CI pipeline to wait for the database to become available.
require 'database_oracle'

namespace :ci_preparation do
  desc "Wait for DB to become available in CI pipeline"

  task :wait_for_db_available, [:max_wait_minutes] do |_, args|
    puts "Running ci_preparation:wait_for_db_available for db_type = #{MovexCdc::Application.config.db_type }"
    max_wait_minutes = args[:max_wait_minutes].to_i
    raise "Parameter wait time in minutes expected" if args.count == 0 || max_wait_minutes == 0
    puts "Waiting max. #{max_wait_minutes} minutes for database to become available"
    start_time = Time.now
    result = ''
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      exception_text = nil
      loop do
        raise "DB not available after waiting #{max_wait_minutes} minutes! Aborting!\nReason: #{exception_text}\n" if Time.now > start_time + max_wait_minutes.minutes

        begin
          conn = DatabaseOracle.connect_as_sys_user

          stmt = conn.prepareStatement("SELECT Instance_name||' ('||Host_Name||') '||Version FROM v$Instance")
          resultSet = stmt.executeQuery;
          resultSet.next
          result = resultSet.getString(1)
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

      puts "\n#{Time.now}: DB is available now: #{result}"
    else
      puts "No action for db_type = #{MovexCdc::Application.config.db_type }"
    end
  end
end