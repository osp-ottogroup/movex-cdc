ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'

class ActiveSupport::TestCase
  # Run tests in parallel with specified workers
  # parallel tests deactivated due to database consistency problems, Ramm, 21.12.2019
  # parallelize(workers: :number_of_processors, with: :threads)

  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all

  setup do
    JdbcInfo.log_version
  end


  # schema for tables with triggers for tests
  def victim_schema_id
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then schemas(:victim).id
    when 'SQLITE' then schemas(:one).id                                         # SQLite does not support multiple schema
    else
      raise "Unsupported value for Trixx::Application.config.trixx_db_type: '#{Trixx::Application.config.trixx_db_type}'"
    end
  end

  # get schemaname if used for DB
  def victim_schema_prefix
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then "#{Trixx::Application.config.trixx_db_victim_user}."
    when 'SQLITE' then ''
    else
      raise "Unsupported value for Trixx::Application.config.trixx_db_type: '#{Trixx::Application.config.trixx_db_type}'"
    end
  end

  def create_victim_connection
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      db_config = Rails.configuration.database_configuration[Rails.env].clone
      db_config['username'] = Trixx::Application.config.trixx_db_victim_user
      db_config['password'] = Trixx::Application.config.trixx_db_victim_password
      db_config.symbolize_keys!
      Rails.logger.debug "create_victim_connection: creating JDBCConnection"
      ActiveRecord::ConnectionAdapters::OracleEnhanced::JDBCConnection.new(db_config)
    when 'SQLITE' then ActiveRecord::Base.connection                            # SQLite uses default AR connection
    else
      raise "Unsupported value for Trixx::Application.config.trixx_db_type: '#{Trixx::Application.config.trixx_db_type}'"
    end
  rescue Exception => e
    ExceptionHelper.log_exception(e, 'create_victim_connection')
    raise
  end

  def logoff_victim_connection(connection)
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then connection.logoff
    when 'SQLITE' then                                                          # SQLite uses default AR connection
    else
      raise "Unsupported value for Trixx::Application.config.trixx_db_type: '#{Trixx::Application.config.trixx_db_type}'"
    end
  end

  def exec_victim_sql(connection, sql)
    ActiveSupport::Notifications.instrumenter.instrument("sql.active_record", sql: sql, name: 'exec_victim_sql') do
      case Trixx::Application.config.trixx_db_type
      when 'ORACLE' then connection.exec sql
      when 'SQLITE' then connection.execute sql                                   # standard method for AR.connection
      else
        raise "Unsupported value for Trixx::Application.config.trixx_db_type: '#{Trixx::Application.config.trixx_db_type}'"
      end
    end
    #Rails.logger.debug "Event_Logs = #{Database.select_one "SELECT COUNT(*) records FROM Event_Logs"}"
  rescue Exception => e
    msg = "#{e.class} #{e.message}\nwhile executing\n#{sql}"
    Rails.logger.error(msg)
    raise msg
  end

  def exec_db_user_sql(sql)
    ActiveRecord::Base.connection.execute sql
  rescue Exception => e
    msg = "#{e.class} #{e.message}\nwhile executing\n#{sql}"
    Rails.logger.error(msg)
    raise msg
  end

  def create_victim_structures(victim_connection)
    # Renove possible pending structures before recreating
    begin
      drop_victim_structures(victim_connection)
    rescue
      nil
    end

    pkey_list = "PRIMARY KEY(ID, Num_Val, Name, Date_Val, TS_Val, Raw_Val)"
    victim1_table = tables(:victim1)
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      exec_victim_sql(victim_connection, "CREATE TABLE #{victim_schema_prefix}#{victim1_table.name} (
        ID NUMBER, Num_Val NUMBER, Name VARCHAR2(20), Char_Name CHAR(1), Date_Val DATE, TS_Val TIMESTAMP(6), Raw_val RAW(20), TSTZ_Val TIMESTAMP(6) WITH TIME ZONE, RowID_Val ROWID, #{pkey_list}
      )")
      exec_victim_sql(victim_connection, "GRANT SELECT ON #{victim_schema_prefix}#{victim1_table.name} TO #{Trixx::Application.config.trixx_db_user}")
      exec_db_user_sql("\
        CREATE TRIGGER #{DbTrigger.build_trigger_name(victim1_table.schema_id, victim1_table.id, 'I')} FOR INSERT ON #{victim_schema_prefix}#{victim1_table.name}
        COMPOUND TRIGGER
          BEFORE STATEMENT IS
          BEGIN
            NULL;
          END BEFORE STATEMENT;
        END TRIXX_Victim1_I;
      ")
      exec_db_user_sql("\
        CREATE TRIGGER #{DbTriggerOracle.trigger_name_prefix}_TO_DROP FOR UPDATE OF Name ON #{victim_schema_prefix}#{victim1_table.name}
        COMPOUND TRIGGER
          BEFORE STATEMENT IS
          BEGIN
            NULL;
          END BEFORE STATEMENT;
        END TRIXX_Victim1_U;
      ")
    when 'SQLITE' then
      exec_victim_sql(victim_connection, "CREATE TABLE #{victim_schema_prefix}#{victim1_table.name} (
        ID NUMBER, Num_Val NUMBER, Name VARCHAR(20), Char_Name CHAR(1), Date_Val DateTime, TS_Val DateTime(6), Raw_Val BLOB, TSTZ_Val DateTime(6), RowID_Val TEXT, #{pkey_list})")
      exec_db_user_sql("\
        CREATE TRIGGER #{DbTrigger.build_trigger_name(victim1_table.schema_id, victim1_table.id, 'I')} INSERT ON #{victim1_table.name}
        BEGIN
          INSERT INTO Event_Logs(Table_ID, Payload) VALUES (4, '{}');
        END;
      ")
      exec_db_user_sql("\
        CREATE TRIGGER TRIXX_VICTIM1_TO_DROP UPDATE ON #{victim1_table.name}
        BEGIN
          INSERT INTO Event_Logs(Table_ID, Payload) VALUES (4, '{}');
        END;
      ")
    else
      raise "Unsupported value for Trixx::Application.config.trixx_db_type: '#{Trixx::Application.config.trixx_db_type}'"
    end
    "PRIMARY KEY(ID, Num_Val, Char_Name, Date_Val, TS_Val, Raw_Val, TSTZ_Val, RowID_Val)"
  end

  def drop_victim_structures(victim_connection)
    exec_victim_sql(victim_connection, "DROP TABLE #{victim_schema_prefix}#{tables(:victim1).name}")
  end

  # create records in Event_Log by trigger on tables(:victim1)
  def create_event_logs_for_test(number_of_records)
    raise "Should create at least 8 records" if number_of_records < 8

    result = DbTrigger.generate_triggers(victim_schema_id)

    assert_instance_of(Hash, result, 'Should return result of type Hash')
    result.assert_valid_keys(:successes, :errors)
    assert_equal(0, result[:errors].count, 'Should not return errors from trigger generation')

    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      date_val  = "SYSDATE"
      ts_val    = "LOCALTIMESTAMP"
      raw_val   = "HexToRaw('FFFF')"
      tstz_val  = "SYSTIMESTAMP"
      rownum    = "RowNum"
    when 'SQLITE' then
      date_val  = "'2020-02-01T12:20:22'"
      ts_val    = "'2020-02-01T12:20:22.999999+01:00'"
      raw_val   = "'FFFF'"
      tstz_val  = "'2020-02-01T12:20:22.999999+01:00'"
      rownum    = 'row_number() over ()'
    else
      raise "Unsupported value for Trixx::Application.config.trixx_db_type: '#{Trixx::Application.config.trixx_db_type}'"
    end

    # create exactly 8 records in Event_Logs
    event_logs_before = Database.select_one "SELECT COUNT(*) records FROM Event_Logs"

    victim_max_id = Database.select_one "SELECT MAX(ID) max_id FROM #{victim_schema_prefix}#{tables(:victim1).name}"
    victim_max_id = 0 if victim_max_id.nil?

    exec_victim_sql(@victim_connection, "INSERT INTO #{victim_schema_prefix}#{tables(:victim1).name} (ID, Num_Val, Name, Char_Name, Date_Val, TS_Val, RAW_VAL, TSTZ_Val)
      VALUES (#{victim_max_id+1}, 1, 'Record1', 'Y', #{date_val}, #{ts_val}, #{raw_val}, #{tstz_val}
      )")
    exec_victim_sql(@victim_connection, "INSERT INTO #{victim_schema_prefix}#{tables(:victim1).name} (ID, Num_Val, Name, Date_Val, TS_Val, RAW_VAL) VALUES (#{victim_max_id+2}, 0.456,    'Record''2', #{date_val}, #{ts_val}, #{raw_val})")
    exec_victim_sql(@victim_connection, "INSERT INTO #{victim_schema_prefix}#{tables(:victim1).name} (ID, Num_Val, Name, Date_Val, TS_Val, RAW_VAL) VALUES (#{victim_max_id+3}, 48.375,   'Record''3', #{date_val}, #{ts_val}, #{raw_val})")
    exec_victim_sql(@victim_connection, "INSERT INTO #{victim_schema_prefix}#{tables(:victim1).name} (ID, Num_Val, Name, Date_Val, TS_Val, RAW_VAL) VALUES (#{victim_max_id+4}, -23.475,  'Record''4', #{date_val}, #{ts_val}, #{raw_val})")

    exec_victim_sql(@victim_connection, "UPDATE #{victim_schema_prefix}#{tables(:victim1).name}  SET Name = 'Record3', RowID_Val = RowID WHERE ID = #{victim_max_id+3}")
    exec_victim_sql(@victim_connection, "UPDATE #{victim_schema_prefix}#{tables(:victim1).name}  SET Name = 'Record4' WHERE ID = #{victim_max_id+4}")
    exec_victim_sql(@victim_connection, "DELETE FROM #{victim_schema_prefix}#{tables(:victim1).name} WHERE ID IN (#{victim_max_id+1}, #{victim_max_id+2})")
    exec_victim_sql(@victim_connection, "UPDATE #{victim_schema_prefix}#{tables(:victim1).name}  SET Name = Name")  # Should not generate records in Event_Logs

    # Next record should not generate record in Event_Logs due to excluding condition
    exec_victim_sql(@victim_connection, "INSERT INTO #{victim_schema_prefix}#{tables(:victim1).name} (ID, Num_Val, Name, Date_Val, TS_Val, RAW_VAL) VALUES (#{victim_max_id+5}, 1, 'EXCLUDE FILTER', #{date_val}, #{ts_val}, #{raw_val})")

    # create the reamining records in Event_Log
    (number_of_records-8).downto(1).each do |i|
      exec_victim_sql(@victim_connection, "INSERT INTO #{victim_schema_prefix}#{tables(:victim1).name} (ID, Num_Val, Name, Char_Name, Date_Val, TS_Val, RAW_VAL, TSTZ_Val)
      VALUES (#{victim_max_id+9+i}, 1, 'Record1', 'Y', #{date_val}, #{ts_val}, #{raw_val}, #{tstz_val}
      )")
    end

    event_logs_after = Database.select_one "SELECT COUNT(*) records FROM Event_Logs"
    assert_equal(event_logs_before+number_of_records, event_logs_after, "Number of event_logs should be increased by #{number_of_records}")

  end

  def log_event_logs_content(options = {})
    puts options[:caption] if options[:caption] && options[:console_output]
    Rails.logger.debug options[:caption] if options[:caption]
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      if Trixx::Application.partitioning
        Database.select_all("SELECT Partition_Name, High_Value FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS'").each do |p|
          record_count = Database.select_one "SELECT COUNT(*) FROM Event_Logs PARTITION (#{p['partition_name']})"
          msg = "Partition #{p['partition_name']}: high_value = '#{p['high_value']}', #{record_count} records"
          puts msg if options[:console_output]
          Rails.logger.debug msg
        end
      end
    end

    msg = "First 100 remaining events in table Event_Logs:"
    puts msg if options[:console_output]
    Rails.logger.debug msg

    counter = 0
    Database.select_all("SELECT * FROM Event_Logs").each do |e|
      counter += 1
      if counter <= 100
        clone = e.clone
        clone['payload'] = clone['payload'][0, 1000]                            # Limit output to fist 1000 chars
        clone['payload'] << "... [content reduced to 1000 chars]" if clone['payload'].length == 1000
        puts clone if options[:console_output]
        Rails.logger.debug clone
      end
    end
  end

  # Process records from event_log and restore previous app state
  def process_eventlogs(options = {})
    options[:max_wait_time]               = 20 unless options[:max_wait_time]
    options[:expected_remaining_records]  = 0  unless options[:expected_remaining_records]

    original_worker_threads = Trixx::Application.config.trixx_initial_worker_threads
    Trixx::Application.config.trixx_initial_worker_threads = 1                # Ensure that all keys are matching to this worker thread by MOD

    log_event_logs_content(console_output: false, caption: "#{options[:title]}: Event_Logs records before processing")

    # worker ID=0 for exactly 1 running worker
    worker = TransferThread.new(0, max_transaction_size: 10000, max_message_bulk_count: 1000, max_buffer_bytesize: 100000)  # Sync. call within one thread

    # Stop process in separate thread after 10 seconds because following call of 'process' will never end without that
    Thread.new do
      loop_count = 0
      while loop_count < options[:max_wait_time] do                           # wait up to x seconds for processing
      loop_count += 1
      event_logs = Database.select_one("SELECT COUNT(*) FROM Event_Logs")
      Rails.logger.debug "#{event_logs} records remaining in Event_Logs"
      break if event_logs == options[:expected_remaining_records]             # All records processed, no need to wait anymore
      sleep 1
      end
      worker.stop_thread
    end

    worker.process                                                            # only synchrone execution ensures valid test of function

    remaining_event_log_count = Database.select_one("SELECT COUNT(*) FROM Event_Logs")
    log_event_logs_content(console_output: true, caption: "#{options[:title]}: Event_Logs records after processing") if remaining_event_log_count > options[:expected_remaining_records]   # List remaining events from table

    Trixx::Application.config.trixx_initial_worker_threads = original_worker_threads  # Restore possibly differing value
    remaining_event_log_count
  end


end

class ActionDispatch::IntegrationTest
  setup do
    # create JWT token for following tests
    @jwt_token                  = jwt_token users(:one).id
    @jwt_admin_token            = jwt_token users(:admin).id
    @jwt_no_schema_right_token  = jwt_token users(:no_schema_right).id

    JdbcInfo.log_version
  end

  def jwt_token(user_id)
    JsonWebToken.encode({user_id: user_id}, 1.hours.from_now)
  end

  # provide JWT token for tests
  def jwt_header(token = @jwt_token)
    { 'Authorization' => token}
  end

end

class JdbcInfo
  @@jdbc_driver_logged = false
  def self.log_version
    unless @@jdbc_driver_logged
      case Trixx::Application.config.trixx_db_type
      when 'ORACLE' then puts "Oracle JDBC driver version = #{ActiveRecord::Base.connection.raw_connection.getMetaData.getDriverVersion}"
      else puts "No JDBC version checked"
      end

      @@jdbc_driver_logged = true
    end
  end
end