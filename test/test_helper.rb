ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'

module TestHelper

  def user_schema;    GlobalFixtures.user_schema;     end # schema for tables without triggers for tests
  def victim_schema;  GlobalFixtures.victim_schema;   end # schema for tables with triggers for tests
  def peter_user;     GlobalFixtures.peter_user;      end
  def sandro_user;    GlobalFixtures.sandro_user;     end
  def tables_table;   GlobalFixtures.tables_table;    end
  def victim1_table;  GlobalFixtures.victim1_table;   end
  def victim2_table;  GlobalFixtures.victim2_table;   end

  # get schemaname if used for DB
  def victim_schema_prefix
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then "#{Trixx::Application.config.trixx_db_victim_user}."
    when 'SQLITE' then ''
    else
      raise "Unsupported value for Trixx::Application.config.trixx_db_type: '#{Trixx::Application.config.trixx_db_type}'"
    end
  end
end

class ActiveSupport::TestCase
  include TestHelper
  # Run tests in parallel with specified workers
  # parallel tests deactivated due to database consistency problems, Ramm, 21.12.2019
  # parallelize(workers: :number_of_processors, with: :threads)

  # Oracle: if current SCN is the same as after last DDL on table then ORA-01466 is raised at "SELECT FROM Tables AS OF SCN ..."
  # solution is to execute test without using savepoints to rollback changes
  self.use_transactional_tests = false

  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all

  setup do
    JdbcInfo.log_version
    Database.initialize_connection                                              # do some init actions for DB connection before use
    GlobalFixtures.initialize                                                   # Create fixtures only once for whole test, not once per particular test
  end

  teardown do
    ThreadHandling.get_instance.shutdown_processing if ThreadHandling.has_instance?
    StatisticCounterConcentrator.remove_instance                                # Ensure next test starts with fresh instance
  end

=begin
  def logoff_victim_connection(connection)
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then connection.logoff
    when 'SQLITE' then                                                          # SQLite uses default AR connection
    else
      raise "Unsupported value for Trixx::Application.config.trixx_db_type: '#{Trixx::Application.config.trixx_db_type}'"
    end
  end
=end

  def user_options_4_test
    { user_id: peter_user.id, client_ip_info: '0.0.0.0'}
  end

  def exec_victim_sql(sql)
    ActiveSupport::Notifications.instrumenter.instrument("sql.active_record", sql: sql, name: 'exec_victim_sql') do
      case Trixx::Application.config.trixx_db_type
      when 'ORACLE' then GlobalFixtures.victim_connection.exec sql
      when 'SQLITE' then GlobalFixtures.victim_connection.execute sql           # standard method for AR.connection
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

  def create_victim_structures
    # Remove possible pending structures before recreating
    exec_drop = proc do |sql|
      exec_victim_sql(sql)
    rescue                                                                      # Ignore drop errors
    end

    exec_drop.call("DROP TABLE #{victim_schema_prefix}VICTIM1")
    exec_drop.call("DROP TABLE #{victim_schema_prefix}VICTIM2")
    exec_drop.call("DROP TABLE #{victim_schema_prefix}VICTIM3")

    pkey_list = "PRIMARY KEY(ID, Num_Val, Name, Date_Val, TS_Val, Raw_Val)"
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      exec_victim_sql("CREATE TABLE #{victim_schema_prefix}#{victim1_table.name} (
        ID NUMBER, Num_Val NUMBER, Name VARCHAR2(20), Char_Name CHAR(1), Date_Val DATE, TS_Val TIMESTAMP(6), Raw_val RAW(20), TSTZ_Val TIMESTAMP(6) WITH TIME ZONE, RowID_Val ROWID, #{pkey_list}
      )")
      exec_victim_sql("GRANT SELECT, FLASHBACK ON #{victim_schema_prefix}#{victim1_table.name} TO #{Trixx::Application.config.trixx_db_user}") # needed for table initialization
      exec_db_user_sql("\
        CREATE TRIGGER #{DbTrigger.build_trigger_name(victim1_table, 'I')} FOR INSERT ON #{victim_schema_prefix}#{victim1_table.name}
        COMPOUND TRIGGER
          BEFORE STATEMENT IS
          BEGIN
            NULL;
          END BEFORE STATEMENT;
        END TRIXX_Victim1_I;
      ")
      exec_db_user_sql("\
        CREATE TRIGGER #{DbTriggerGeneratorOracle::TRIGGER_NAME_PREFIX}_TO_DROP FOR UPDATE OF Name ON #{victim_schema_prefix}#{victim1_table.name}
        COMPOUND TRIGGER
          BEFORE STATEMENT IS
          BEGIN
            NULL;
          END BEFORE STATEMENT;
        END TRIXX_Victim1_U;
      ")

      exec_victim_sql("CREATE TABLE #{victim_schema_prefix}VICTIM2 (ID NUMBER, Large_Text CLOB, PRIMARY KEY (ID))")
      exec_victim_sql("GRANT SELECT ON #{victim_schema_prefix}VICTIM2 TO #{Trixx::Application.config.trixx_db_user}")
      # Table VICTIM3 without fixture in Tables
      exec_victim_sql("CREATE TABLE #{victim_schema_prefix}VICTIM3 (ID NUMBER, Name VARCHAR2(20), PRIMARY KEY (ID))")
    when 'SQLITE' then
      exec_victim_sql("CREATE TABLE #{victim_schema_prefix}#{victim1_table.name} (
        ID NUMBER, Num_Val NUMBER, Name VARCHAR(20), CHAR_NAME CHAR(1), Date_Val DateTime, TS_Val DateTime(6), Raw_Val BLOB, TSTZ_Val DateTime(6), RowID_Val TEXT, #{pkey_list})")
      exec_db_user_sql("\
        CREATE TRIGGER #{DbTrigger.build_trigger_name(victim1_table, 'I')} INSERT ON #{victim1_table.name}
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
      exec_victim_sql("CREATE TABLE #{victim_schema_prefix}VICTIM2 (ID NUMBER, Large_Text CLOB, PRIMARY KEY (ID))")
      # Table VICTIM3 without fixture in Tables
      exec_victim_sql("CREATE TABLE #{victim_schema_prefix}VICTIM3 (ID NUMBER, Name VARCHAR(20), PRIMARY KEY (ID))")
    else
      raise "Unsupported value for Trixx::Application.config.trixx_db_type: '#{Trixx::Application.config.trixx_db_type}'"
    end
  end

  # create records in Event_Log by trigger on VICTIM1
  def create_event_logs_for_test(number_of_records)
    raise "Should create at least 11 records" if number_of_records < 11
    if ThreadHandling.get_instance.thread_count > 0
      msg = "There are already #{ThreadHandling.get_instance.thread_count} running worker threads! Created Event_Logs will be processed immediately!"
      Rails.logger.debug msg
      raise msg
    end

    result = DbTrigger.generate_schema_triggers(schema_id: victim_schema.id, user_options: user_options_4_test)

    assert_instance_of(Hash, result, 'Should return result of type Hash')
    result.assert_valid_keys(:successes, :errors, :load_sqls)
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

    # create exactly 8 records in Event_Logs for Victim1
    event_logs_before = Database.select_one "SELECT COUNT(*) records FROM Event_Logs"

    victim_max_id = Database.select_one "SELECT MAX(ID) max_id FROM #{victim_schema_prefix}VICTIM1"
    victim_max_id = 0 if victim_max_id.nil?

    ActiveRecord::Base.transaction do
      # First 4 I events
      exec_victim_sql("INSERT INTO #{victim_schema_prefix}VICTIM1 (ID, Num_Val, Name, Char_Name, Date_Val, TS_Val, RAW_VAL, TSTZ_Val)
      VALUES (#{victim_max_id+1}, 1, 'Record1', 'Y', #{date_val}, #{ts_val}, #{raw_val}, #{tstz_val}
      )")
      exec_victim_sql("INSERT INTO #{victim_schema_prefix}VICTIM1 (ID, Num_Val, Name, Date_Val, TS_Val, RAW_VAL) VALUES (#{victim_max_id+2}, 0.456,    'Record''2', #{date_val}, #{ts_val}, #{raw_val})")
      exec_victim_sql("INSERT INTO #{victim_schema_prefix}VICTIM1 (ID, Num_Val, Name, Date_Val, TS_Val, RAW_VAL) VALUES (#{victim_max_id+3}, 48.375,   'Record''3', #{date_val}, #{ts_val}, #{raw_val})")
      exec_victim_sql("INSERT INTO #{victim_schema_prefix}VICTIM1 (ID, Num_Val, Name, Date_Val, TS_Val, RAW_VAL) VALUES (#{victim_max_id+4}, -23.475,  'Record''4', #{date_val}, #{ts_val}, #{raw_val})")

      # 2 U events
      exec_victim_sql("UPDATE #{victim_schema_prefix}VICTIM1  SET Name = 'Record3', RowID_Val = RowID WHERE ID = #{victim_max_id+3}")
      exec_victim_sql("UPDATE #{victim_schema_prefix}VICTIM1  SET Name = 'Record4' WHERE ID = #{victim_max_id+4}")
      # 2 D events
      exec_victim_sql("DELETE FROM #{victim_schema_prefix}VICTIM1 WHERE ID IN (#{victim_max_id+1}, #{victim_max_id+2})")
      exec_victim_sql("UPDATE #{victim_schema_prefix}VICTIM1  SET Name = Name")  # Should not generate records in Event_Logs

      # Next record should not generate record in Event_Logs due to excluding condition
      exec_victim_sql("INSERT INTO #{victim_schema_prefix}VICTIM1 (ID, Num_Val, Name, Date_Val, TS_Val, RAW_VAL) VALUES (#{victim_max_id+5}, 1, 'EXCLUDE FILTER', #{date_val}, #{ts_val}, #{raw_val})")

      # create exactly 3 records in Event_Logs for Victim2
      victim2_max_id = Database.select_one "SELECT MAX(ID) max_id FROM #{victim_schema_prefix}VICTIM2"
      victim2_max_id = 0 if victim2_max_id.nil?

      case Trixx::Application.config.trixx_db_type
      when 'ORACLE'
        # create content > 4K in CLOB column
        exec_victim_sql("
      DECLARE
        clob_content CLOB := '';
      BEGIN
        FOR i IN 1..100 LOOP
          clob_content  := clob_content || '0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789';
        END LOOP;
        INSERT INTO #{victim_schema_prefix}VICTIM2 (ID, Large_Text) VALUES (#{victim2_max_id+1}, clob_content);
      END;
      ")
      when 'SQLITE'
        exec_victim_sql("INSERT INTO #{victim_schema_prefix}VICTIM2 (ID, Large_Text) VALUES (#{victim2_max_id+1}, '01234567890123456789')")
      end
      exec_victim_sql("UPDATE #{victim_schema_prefix}VICTIM2  SET Large_Text = 'small text' WHERE ID = #{victim2_max_id+1}")
      exec_victim_sql("DELETE FROM #{victim_schema_prefix}VICTIM2 WHERE ID = #{victim2_max_id+1}")

      # create the reamining records in Event_Log
      (number_of_records-(8+3)).downto(1).each do |i|
        exec_victim_sql("INSERT INTO #{victim_schema_prefix}VICTIM1 (ID, Num_Val, Name, Char_Name, Date_Val, TS_Val, RAW_VAL, TSTZ_Val)
      VALUES (#{victim_max_id+9+i}, 1, 'Record1', 'Y', #{date_val}, #{ts_val}, #{raw_val}, #{tstz_val}
      )")
      end
    end # COMMIT

    event_logs_after = Database.select_one "SELECT COUNT(*) records FROM Event_Logs"
    if event_logs_before+number_of_records != event_logs_after
      msg = "Number of event_logs should be increased by #{number_of_records} but before are #{event_logs_before} records and after are #{event_logs_after} records"
      Rails.logger.error msg
      log_event_logs_content
      raise msg
    end
  end

  def log_event_logs_content(options = {})
    puts options[:caption] if options[:caption] && options[:console_output]
    Rails.logger.debug options[:caption] if options[:caption]
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      if Trixx::Application.partitioning?
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
    Database.select_all("SELECT * FROM Event_Logs ORDER BY ID").each do |e|
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
        break if event_logs == options[:expected_remaining_records]           # All records processed, no need to wait anymore
        sleep 1
      end
      worker.stop_thread
    end

    worker.process                                                            # only synchrone execution ensures valid test of function

    remaining_event_log_count = Database.select_one("SELECT COUNT(*) FROM Event_Logs")
    log_event_logs_content(console_output: true, caption: "#{options[:title]}: #{remaining_event_log_count} Event_Logs records after processing") if remaining_event_log_count > options[:expected_remaining_records]   # List remaining events from table

    Trixx::Application.config.trixx_initial_worker_threads = original_worker_threads  # Restore possibly differing value
    remaining_event_log_count
  end

  # check for exact value (max_expected = nil) or range (expected .. max_expected)
  def assert_statistics(expected:, table_id:, operation:, column_name:, max_expected: nil)
    result = Database.select_one "SELECT SUM(#{column_name}) Value
                                  FROM   Statistics
                                  WHERE  Table_ID  = :table_id
                                  AND    Operation = :operation
                                 ", { table_id: table_id, operation: operation}
    if max_expected.nil?
      assert_equal expected, result, "Expected Statistics value for Table_ID=#{table_id} Name='#{Table.find(table_id).name}', Operation='#{operation}', Column='#{column_name}'"
    else
      assert result >= expected && result <= max_expected, "Statistics value #{result} not between #{expected} and #{max_expected} for Table_ID=#{table_id} Name='#{Table.find(table_id).name}, Operation='#{operation}', Column='#{column_name}'"
    end
  end

end

class ActionDispatch::IntegrationTest
  include TestHelper

  self.use_transactional_tests = false                                        # Like ActiveSupport::TestCase don't rollback transactions
  setup do
    JdbcInfo.log_version
    Database.initialize_connection                                              # do some init actions for DB connection before use
    GlobalFixtures.initialize                                                   # Create fixtures only once for whole test, not once per particular test

    # create JWT token for following tests
    @jwt_token                  = jwt_token peter_user.id
    @jwt_admin_token            = jwt_token User.where(email: 'admin').first.id
    @jwt_no_schema_right_token  = jwt_token User.where(email: 'no_schema_right@xy.com').first.id
  end

  teardown do
    if ThreadHandling.has_instance?
      ThreadHandling.get_instance.shutdown_processing
      raise "ThreadHandling.get_instance.shutdown_processing not successful" if ThreadHandling.get_instance.thread_count(raise_exception_if_locked: true) != 0
    end
    StatisticCounterConcentrator.remove_instance                                # Ensure next test starts with fresh instance
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

class GlobalFixtures

  @@global_fixtures_initialized = false
  def self.initialize
    unless @@global_fixtures_initialized
      # Fixtures to load only once
      @@global_fixtures_initialized = true                                      # call only once at start of test suite

      ActiveRecord::Base.transaction do
        EventLog.delete_all
        Database.execute "DELETE FROM event_log_final_errors"
        ActivityLog.delete_all
        SchemaRight.delete_all
        User.delete_all
        Condition.delete_all
        Column.delete_all
        Table.delete_all
        Schema.delete_all

        # load admin from DB each time because ID may change
        User.new(email: 'admin',                        db_user: Trixx::Application.config.trixx_db_user,         first_name: 'Admin',  last_name: 'from fixture', yn_admin: 'Y').save!
        @@peter_user = User.new(email: 'Peter.Ramm@ottogroup.com',     db_user: Trixx::Application.config.trixx_db_victim_user,  first_name: 'Peter',  last_name: 'Ramm')
        @@peter_user.save!
        @@sandro_user = User.new(email: 'Sandro.Preuss@ottogroup.com',  db_user: Trixx::Application.config.trixx_db_victim_user,  first_name: 'Sandro', last_name: 'Preuß')
        @@sandro_user.save!
        @@no_schema_user = User.new(email: 'no_schema_right@xy.com',       db_user: Trixx::Application.config.trixx_db_victim_user,  first_name: 'No',     last_name: 'Schema')
        @@no_schema_user.save!

        @@user_schema = Schema.new(name: Trixx::Application.config.trixx_db_user, topic: KafkaHelper.existing_topic_for_test)
        @@user_schema.save!

        if Trixx::Application.config.trixx_db_type != 'SQLITE'
          @@victim_schema = Schema.new(name: Trixx::Application.config.trixx_db_victim_user, topic: KafkaHelper.existing_topic_for_test)
          @@victim_schema.save!
          Schema.new(name: 'WITHOUT_TOPIC').save!
        else
          @@victim_schema = @@user_schema
        end

        restore_schema_rights

        # 1
        @@tables_table = Table.new(schema_id:  @@user_schema.id,
                                   name:       'TABLES',
                                   info:       'Mein Text',
                                   topic:      KafkaHelper.existing_topic_for_test
        )
        @@tables_table.save!

        # 2
        @@columns_table = Table.new(schema_id:  @@user_schema.id,
                          name:       'COLUMNS',
                          info:       'Mein Text',
                          topic:      KafkaHelper.existing_topic_for_test
        )
        @@columns_table.save!

        # 4
        @@victim1_table = Table.new(schema_id:  @@victim_schema.id,
                                    name:       'VICTIM1',
                                    info:       'Victim table in separate schema for use with triggers. Does not contain CLOB column.',
                                    topic:      KafkaHelper.existing_topic_for_test
        )
        @@victim1_table.save!

        # 5
        @@victim2_table = Table.new(schema_id:  @@victim_schema.id,
                                    name:       'VICTIM2',
                                    info:       'Victim table in separate schema for use with triggers. Contains CLOB column.',
                                    topic:      KafkaHelper.existing_topic_for_test
        )
        @@victim2_table.save!

        Column.new(table_id: @@tables_table.id, name: 'SCHEMA_ID', info: 'Mein Text', yn_log_insert: 'N', yn_log_update: 'N', yn_log_delete: 'N').save!
        Condition.new(table_id: @@tables_table.id, operation: 'I', filter: 'ID IS NOT NULL').save!
        Condition.new(table_id: @@tables_table.id, operation: 'D', filter: 'ID IS NOT NULL').save!

        Column.new(table_id: @@columns_table.id, name: 'TABLE_ID', info: 'Mein Text', yn_log_insert: 'N', yn_log_update: 'N', yn_log_delete: 'N').save!

        Column.new(table_id: @@victim1_table.id, name: 'ID',        info: 'Number test',    yn_log_insert: 'Y', yn_log_update: 'Y', yn_log_delete: 'Y').save!
        Column.new(table_id: @@victim1_table.id, name: 'NAME',      info: 'Varchar2 test',  yn_log_insert: 'Y', yn_log_update: 'Y', yn_log_delete: 'Y').save!
        Column.new(table_id: @@victim1_table.id, name: 'CHAR_NAME', info: 'Char test',      yn_log_insert: 'Y', yn_log_update: 'Y', yn_log_delete: 'Y').save!
        Column.new(table_id: @@victim1_table.id, name: 'DATE_VAL',  info: 'Date test',      yn_log_insert: 'Y', yn_log_update: 'Y', yn_log_delete: 'Y').save!
        Column.new(table_id: @@victim1_table.id, name: 'TS_VAL',    info: 'Timestamp test', yn_log_insert: 'Y', yn_log_update: 'Y', yn_log_delete: 'Y').save!
        Column.new(table_id: @@victim1_table.id, name: 'RAW_VAL',   info: 'Raw test',       yn_log_insert: 'Y', yn_log_update: 'Y', yn_log_delete: 'Y').save!
        Column.new(table_id: @@victim1_table.id, name: 'TSTZ_VAL',  info: 'TS with TZ test',yn_log_insert: 'Y', yn_log_update: 'Y', yn_log_delete: 'Y').save!
        Column.new(table_id: @@victim1_table.id, name: 'ROWID_VAL', info: 'RowID test',     yn_log_insert: 'Y', yn_log_update: 'Y', yn_log_delete: 'Y').save!
        Column.new(table_id: @@victim1_table.id, name: 'NUM_VAL',   info: 'NumVal test',    yn_log_insert: 'Y', yn_log_update: 'Y', yn_log_delete: 'Y').save!
        Condition.new(table_id: @@victim1_table.id, operation: 'I',
                      filter: case Trixx::Application.config.trixx_db_type
                              when 'ORACLE' then ":new.Name != 'EXCLUDE FILTER'"
                              when 'SQLITE' then "new.Name != 'EXCLUDE FILTER'"
                              end
        ).save!
        Condition.new(table_id: @@victim1_table.id, operation: 'D',
                      filter: case Trixx::Application.config.trixx_db_type
                              when 'ORACLE' then ":old.ID IS NOT NULL"
                              when 'SQLITE' then "old.ID IS NOT NULL"
                              end
        ).save!

        Column.new(table_id: @@victim2_table.id, name: 'ID',          info: 'CLOB test',    yn_log_insert: 'Y', yn_log_update: 'Y', yn_log_delete: 'Y').save!
        Column.new(table_id: @@victim2_table.id, name: 'LARGE_TEXT',  info: 'CLOB test',    yn_log_insert: 'Y', yn_log_update: 'Y', yn_log_delete: 'Y').save!
      end

      @@victim_connection = case Trixx::Application.config.trixx_db_type
                            when 'ORACLE' then
                              db_config = Rails.configuration.database_configuration[Rails.env].clone
                              db_config['username'] = Trixx::Application.config.trixx_db_victim_user
                              db_config['password'] = Trixx::Application.config.trixx_db_victim_password
                              db_config.symbolize_keys!
                              Rails.logger.debug "create_victim_connection: creating JDBCConnection"
                              ActiveRecord::ConnectionAdapters::OracleEnhanced::JDBCConnection.new(db_config)
                            end

    end
  end

  # Ensure all necessary schema_rights exists
  def self.restore_schema_rights
    schema_right = SchemaRight.where(user_id: peter_user.id, schema_id: @@user_schema.id).first
    if schema_right.nil?
      SchemaRight.new(user_id:    peter_user.id,
                      schema_id:  user_schema.id,
                      info:       'Info1',
                      yn_deployment_granted: 'Y'
      ).save!
    else
      schema_right.update!(yn_deployment_granted: 'Y')
    end

    if Trixx::Application.config.trixx_db_type != 'SQLITE'
      schema_right = SchemaRight.where(user_id: peter_user.id, schema_id: @@victim_schema.id).first
      if schema_right.nil?
        SchemaRight.new(user_id:    peter_user.id,
                        schema_id:  victim_schema.id,
                        info:       'Info2',
                        yn_deployment_granted: 'Y'
        ).save!
      else
        schema_right.update!(yn_deployment_granted: 'Y')
      end
    end
  end

  def self.user_schema;       @@user_schema;        end
  def self.victim_schema;     @@victim_schema;      end
  def self.peter_user;        @@peter_user;         end
  def self.sandro_user;       @@sandro_user;        end
  def self.sandro_user;       @@sandro_user;        end
  def self.tables_table;      @@tables_table;       end
  def self.victim1_table;     @@victim1_table;      end
  def self.victim2_table;     @@victim2_table;      end

  def self.victim_connection
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then @@victim_connection
    when 'SQLITE' then ActiveRecord::Base.connection                            # use currently active connection
    end
  end

  # initialize again after global changes of IDs and content, e.g. from import
  def self.reinitialize
    @@global_fixtures_initialized = false
    initialize
  end

end