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
  def victim4_table;  GlobalFixtures.victim4_table;   end

  # get schemaname if used for DB
  def victim_schema_prefix
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then "#{MovexCdc::Application.config.db_victim_user}."
    when 'SQLITE' then ''
    else
      raise "Unsupported value for MovexCdc::Application.config.db_type: '#{MovexCdc::Application.config.db_type}'"
    end
  end

  # allow assertions failure message to appear in logfile
  # use like: assert_response :success, log_on_failure('should get log file with JWT')
  def log_on_failure(message)
    Proc.new do
      Rails.logger.debug('TestHelper.log_on_failure'){ "Assertion failed: #{message}" }
      message
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
    Database.initialize_db_connection                                              # do some init actions for DB connection before use
    GlobalFixtures.initialize_testdata                                                   # Create fixtures only once for whole test, not once per particular test
    @test_start_time = Time.now
    Rails.logger.info('ActiveSupport::TestCase.setup') { "#{@test_start_time} : start of test #{self.class}.#{self.name}" } # set timestamp in test.logs
  end

  teardown do
    ThreadHandling.get_instance.shutdown_processing if ThreadHandling.has_instance?
    StatisticCounterConcentrator.remove_instance                                # Ensure next test starts with fresh instance
    @test_end_time = Time.now
    Rails.logger.info('ActiveSupport::TestCase.teardown') { "#{@test_end_time} : end of test #{self.class}.#{self.name}" } # set timestamp in test.logs
    Rails.logger.info('ActiveSupport::TestCase.teardown') { "#{(@test_end_time-@test_start_time).round(2)} seconds for test #{self.class}.#{self.name}" } # set timestamp in test.logs
    Rails.logger.info('ActiveSupport::TestCase.teardown') { '' }
  end

  # Execute block with valid current user
  def run_with_current_user
    unless Thread.current[:current_user].nil?
      msg = "Current user is already set! run_with_current_user should not be used recursive!"
      Rails.logger.error('TestHelper.run_with_current_user') { msg }
      raise msg
    end
    ApplicationController.set_current_user(peter_user)
    ApplicationController.set_current_client_ip_info('test-IP')
    yield                                                                       # execute block and return result
  ensure
    ApplicationController.unset_current_user
    ApplicationController.unset_current_client_ip_info
  end

  def exec_victim_sql(sql)
    ActiveSupport::Notifications.instrumenter.instrument("sql.active_record", sql: sql, name: 'exec_victim_sql') do
      case MovexCdc::Application.config.db_type
      when 'ORACLE' then GlobalFixtures.victim_connection.exec sql
      when 'SQLITE' then GlobalFixtures.victim_connection.execute sql           # standard method for AR.connection
      else
        raise "Unsupported value for MovexCdc::Application.config.db_type: '#{MovexCdc::Application.config.db_type}'"
      end
    end
  rescue Exception => e
    msg = "#{e.class} #{e.message}\nwhile executing\n#{sql}"
    Rails.logger.error('ActiveSupport::TestCase.exec_victim_sql'){ msg }
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
    exec_drop.call("DROP TABLE #{victim_schema_prefix}VICTIM4")

    pkey_list = "PRIMARY KEY(ID, Num_Val, Name, Date_Val, TS_Val, Raw_Val)"
    victim1_drop_trigger_name = "#{DbTriggerGeneratorOracle::TRIGGER_NAME_PREFIX}I_#{victim_schema.id}_#{victim1_table.id}_TO_DROP"
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      exec_victim_sql("CREATE TABLE #{victim_schema_prefix}#{victim1_table.name} (
        ID NUMBER, Num_Val NUMBER, Name VARCHAR2(20), Char_Name CHAR(1), Date_Val DATE, TS_Val TIMESTAMP(6), Raw_val RAW(20), TSTZ_Val TIMESTAMP(6) WITH TIME ZONE, RowID_Val ROWID, #{pkey_list}
      )")
      # Ensure uniqueness of ID even if other PKey is used to test event keys from primary key columns
      exec_victim_sql("CREATE UNIQUE INDEX  #{victim_schema_prefix}UX_#{victim1_table.name} ON #{victim_schema_prefix}#{victim1_table.name}(ID)")
      exec_victim_sql("GRANT SELECT, FLASHBACK ON #{victim_schema_prefix}#{victim1_table.name} TO #{MovexCdc::Application.config.db_user}") # needed for table initialization
      Database.exec_unprepared("\
        CREATE TRIGGER #{DbTrigger.build_trigger_name(victim1_table, 'I')} FOR INSERT ON #{victim_schema_prefix}#{victim1_table.name}
        COMPOUND TRIGGER
          BEFORE STATEMENT IS
          BEGIN
            NULL;
          END BEFORE STATEMENT;
        END #{DbTrigger.build_trigger_name(victim1_table, 'I')};
      ")
      Database.exec_unprepared("\
        CREATE TRIGGER #{victim1_drop_trigger_name} FOR UPDATE OF Name ON #{victim_schema_prefix}#{victim1_table.name}
        COMPOUND TRIGGER
          BEFORE STATEMENT IS
          BEGIN
            NULL;
          END BEFORE STATEMENT;
        END #{victim1_drop_trigger_name};
      ")

      exec_victim_sql("CREATE TABLE #{victim_schema_prefix}VICTIM2 (ID NUMBER, Name VARCHAR2(20), Large_Text CLOB, PRIMARY KEY (ID))")
      exec_victim_sql("GRANT SELECT ON #{victim_schema_prefix}VICTIM2 TO #{MovexCdc::Application.config.db_user}")
      # Table VICTIM3 without fixture in Tables
      exec_victim_sql("CREATE TABLE #{victim_schema_prefix}VICTIM3 (ID NUMBER, Name VARCHAR2(20), PRIMARY KEY (ID))")
      exec_victim_sql("CREATE TABLE #{victim_schema_prefix}VICTIM4 (ID NUMBER, Name VARCHAR2(20))") # without pkey
    when 'SQLITE' then
      exec_victim_sql("CREATE TABLE #{victim_schema_prefix}#{victim1_table.name} (
        ID NUMBER, Num_Val NUMBER, Name VARCHAR(20), CHAR_NAME CHAR(1), Date_Val DateTime, TS_Val DateTime(6), Raw_Val BLOB, TSTZ_Val DateTime(6), RowID_Val TEXT, #{pkey_list})")
      Database.exec_unprepared("\
        CREATE TRIGGER #{DbTrigger.build_trigger_name(victim1_table, 'I')} INSERT ON #{victim1_table.name}
        BEGIN
          DELETE FROM Event_Logs WHERE 1=2;
        END;
      ")
      Database.exec_unprepared("\
        CREATE TRIGGER #{victim1_drop_trigger_name} UPDATE ON #{victim1_table.name}
        BEGIN
          DELETE FROM Event_Logs WHERE 1=2;
        END;
      ")
      exec_victim_sql("CREATE TABLE #{victim_schema_prefix}VICTIM2 (ID NUMBER, Large_Text CLOB, Name VARCHAR(20), PRIMARY KEY (ID))")
      # Table VICTIM3 without fixture in Tables
      exec_victim_sql("CREATE TABLE #{victim_schema_prefix}VICTIM3 (ID NUMBER, Name VARCHAR(20), PRIMARY KEY (ID))")
      exec_victim_sql("CREATE TABLE #{victim_schema_prefix}VICTIM4 (ID NUMBER, Name VARCHAR(20))") # without pkey
    else
      raise "Unsupported value for MovexCdc::Application.config.db_type: '#{MovexCdc::Application.config.db_type}'"
    end
  end

  # create records in Event_Log by trigger on VICTIM1, current_user should be set outside
  def create_event_logs_for_test(number_of_records)
    raise "Should create at least 11 records" if number_of_records < 11
    if ThreadHandling.get_instance.thread_count > 0
      msg = "There are already #{ThreadHandling.get_instance.thread_count} running worker threads! Created Event_Logs will be processed immediately!"
      Rails.logger.debug('ActiveSupport::TestCase.create_event_logs_for_test'){ msg }
      raise msg
    end

    result = DbTrigger.generate_schema_triggers(schema_id: victim_schema.id)

    assert_instance_of(Hash, result, 'Should return result of type Hash')
    result.assert_valid_keys(:successes, :errors, :load_sqls)
    assert_equal(0, result[:errors].count, "Should not return errors from trigger generation: #{result[:errors].inspect}")

    # create exactly 8 records in Event_Logs for Victim1
    event_logs_before = Database.select_one "SELECT COUNT(*) records FROM Event_Logs"
    Rails.logger.debug('ActiveSupport::TestCase.create_event_logs_for_test'){ "#{event_logs_before} records exist in table Event_Logs" }

    victim_max_id = Database.select_one "SELECT MAX(ID) max_id FROM #{victim_schema_prefix}VICTIM1"
    victim_max_id = 0 if victim_max_id.nil?

    ActiveRecord::Base.transaction do
      # First 4 I events
      insert_victim1_records(number_of_records_to_insert: 1, last_max_id: victim_max_id,    num_val: 1,         log_count: true)
      insert_victim1_records(number_of_records_to_insert: 1, last_max_id: victim_max_id+1,  num_val: 0.456,     log_count: true)
      insert_victim1_records(number_of_records_to_insert: 1, last_max_id: victim_max_id+2,  num_val: 48.375,    log_count: true)
      insert_victim1_records(number_of_records_to_insert: 1, last_max_id: victim_max_id+3,  num_val: -23.475,   log_count: true)
      log_event_logs_count(expected_count: event_logs_before + 4, location: 'First 4 inserts')

      # 2 U events
      exec_victim_sql("UPDATE #{victim_schema_prefix}VICTIM1  SET Name = 'Record3', RowID_Val = RowID WHERE ID = #{victim_max_id+3}")
      log_event_logs_count(expected_count: event_logs_before + 5, location: 'Update Record3')
      exec_victim_sql("UPDATE #{victim_schema_prefix}VICTIM1  SET Name = 'Record4' WHERE ID = #{victim_max_id+4}")
      log_event_logs_count(expected_count: event_logs_before + 6, location: 'Update Record4')
      # 2 D events
      exec_victim_sql("DELETE FROM #{victim_schema_prefix}VICTIM1 WHERE ID IN (#{victim_max_id+1}, #{victim_max_id+2})")
      log_event_logs_count(expected_count: event_logs_before + 8, location: 'Delete 2 records')
      exec_victim_sql("UPDATE #{victim_schema_prefix}VICTIM1  SET Name = Name")  # Should not generate records in Event_Logs
      log_event_logs_count(expected_count: event_logs_before + 8, location: 'Update without Event_Log')

      # Next record should not generate record in Event_Logs due to excluding condition
      insert_victim1_records(number_of_records_to_insert: 1, last_max_id: victim_max_id+4,  name: 'EXCLUDE FILTER', num_val: -23.475,   log_count: true)
      log_event_logs_count(expected_count: event_logs_before + 8, location: 'Insert without event_log')

      # create exactly 3 records in Event_Logs for Victim2
      victim2_max_id = Database.select_one "SELECT MAX(ID) max_id FROM #{victim_schema_prefix}VICTIM2"
      victim2_max_id = 0 if victim2_max_id.nil?

      case MovexCdc::Application.config.db_type
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
      log_event_logs_count(expected_count: event_logs_before + 9, location: 'Insert large content')
      exec_victim_sql("UPDATE #{victim_schema_prefix}VICTIM2  SET Large_Text = 'small text' WHERE ID = #{victim2_max_id+1}")
      log_event_logs_count(expected_count: event_logs_before + 10, location: 'Update large content to small content')
      exec_victim_sql("DELETE FROM #{victim_schema_prefix}VICTIM2 WHERE ID = #{victim2_max_id+1}")
      log_event_logs_count(expected_count: event_logs_before + 11, location: 'Delete one Record by ID')
      # In Oracle 12.2 this delete-trigger may fire twice due to a bug

      # create the remaining records in Event_Log
      insert_victim1_records(number_of_records_to_insert: number_of_records-(8+3), last_max_id: victim_max_id+9, log_count: true)
    end # COMMIT

    event_logs_after = Database.select_one "SELECT COUNT(*) records FROM Event_Logs"
    Rails.logger.debug('ActiveSupport::TestCase.create_event_logs_for_test'){ "#{event_logs_after} records exist in table Event_Logs" }
    if event_logs_before+number_of_records != event_logs_after
      msg = "Number of event_logs should be increased by #{number_of_records} but before are #{event_logs_before} records and after are #{event_logs_after} records"
      Rails.logger.error('ActiveSupport::TestCase.create_event_logs_for_test'){ msg }
      log_event_logs_content
      raise msg
    end
  end

  # Options for mesg key handling to test
  # @return [Array] of Hash with options { kafka_key_handling, fixed_message_key, yn_record_txid, key_expression }
  def key_handling_options
    key_expression_1 = case MovexCdc::Application.config.db_type
                       when 'ORACLE' then ":new.Name"
                       when 'SQLITE' then "new.NAME"  # SQLITE does not support colon before new/old
                       end
    key_expression_2 = case MovexCdc::Application.config.db_type
                       when 'ORACLE' then "SELECT :new.Name FROM DUAL"  # Should be executed into variable
                       when 'SQLITE' then "SELECT new.NAME"  # SQLITE does not support colon before new/old
                       end

    [
      {kafka_key_handling: 'N', fixed_message_key: nil,     yn_record_txid: 'N'},
      {kafka_key_handling: 'P', fixed_message_key: nil,     yn_record_txid: 'Y'},
      {kafka_key_handling: 'F', fixed_message_key: 'hugo',  yn_record_txid: 'N'},
      {kafka_key_handling: 'T', fixed_message_key: nil,     yn_record_txid: 'Y'},
      {kafka_key_handling: 'E', fixed_message_key: nil,     yn_record_txid: 'Y', key_expression: key_expression_1},
      {kafka_key_handling: 'E', fixed_message_key: nil,     yn_record_txid: 'Y', key_expression: key_expression_2},
    ]
  end

  def insert_victim1_records(number_of_records_to_insert:, last_max_id:, name: 'Record', num_val: 1, log_count: false, expected_count: nil)
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      date_val  = "SYSDATE"
      ts_val    = "LOCALTIMESTAMP"
      raw_val   = "HexToRaw('FFFF')"
      tstz_val  = "SYSTIMESTAMP  AT TIME ZONE '+03:00'"                         # Ensure valid time zone is exported
      rownum    = "RowNum"
    when 'SQLITE' then
      date_val  = "'2020-02-01T12:20:22'"
      ts_val    = "'2020-02-01T12:20:22.999999+01:00'"
      raw_val   = "'FFFF'"
      tstz_val  = "'2020-02-01T12:20:22.999999+01:00'"
      rownum    = 'row_number() over ()'
    else
      raise "Unsupported value for MovexCdc::Application.config.db_type: '#{MovexCdc::Application.config.db_type}'"
    end

    number_of_records_to_insert.downto(1).each do |i|
      exec_victim_sql("INSERT INTO #{victim_schema_prefix}VICTIM1 (ID, Num_Val, Name, Char_Name, Date_Val, TS_Val, RAW_VAL, TSTZ_Val)
        VALUES (#{last_max_id+i}, #{num_val}, '#{name}', 'Y', #{date_val}, #{ts_val}, #{raw_val}, #{tstz_val}
        )")
      log_event_logs_count(expected_count: expected_count) if log_count
    end
  end

  def log_event_logs_count(expected_count: nil, location: nil)
    event_logs_count = Database.select_one "SELECT COUNT(*) records FROM Event_Logs"
    Rails.logger.debug('ActiveSupport::TestCase.log_event_logs_count'){ "Table Event_Logs now contains #{event_logs_count} records" }
    if expected_count && expected_count != event_logs_count
      msg = "Number of records in Event_Logs should be #{expected_count} now but is #{event_logs_count}#{" at '#{location}'" if location}"
      Rails.logger.error('TestHelper.log_event_logs_count') { msg }
      raise msg
    end
  end

  def log_event_logs_content(options = {})
    puts options[:caption] if options[:caption] && options[:console_output]
    Rails.logger.debug('ActiveSupport::TestCase.log_event_logs_content'){ options[:caption] if options[:caption] }
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      if MovexCdc::Application.partitioning?
        Database.select_all("SELECT Partition_Name, Partition_Position, High_Value, Interval FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' ORDER BY Partition_Position").each do |p|
          record_count = Database.select_one "SELECT COUNT(*) FROM Event_Logs PARTITION (#{p['partition_name']})"
          msg = "Partition #{p['partition_name']}: position=#{p.partition_position} high_value='#{p.high_value}' interval=#{p.interval}, #{record_count} records"
          puts msg if options[:console_output]
          Rails.logger.debug('ActiveSupport::TestCase.log_event_logs_content'){ msg }
        end
      end
    end

    msg = "First 20 remaining events in table Event_Logs:"
    puts msg if options[:console_output]
    Rails.logger.debug('ActiveSupport::TestCase.log_event_logs_content'){ msg }

    counter = 0
    Database.select_all("SELECT * FROM Event_Logs ORDER BY ID").each do |e|
      counter += 1
      if counter <= 20
        clone = e.clone
        clone['payload'] = clone['payload'][0, 1000]                            # Limit output to fist 1000 chars
        clone['payload'] << "... [content reduced to 1000 chars]" if clone['payload'].length == 1000
        puts clone if options[:console_output]
        Rails.logger.debug('ActiveSupport::TestCase.log_event_logs_content'){ clone }
      end
    end
  end

  # Process records from event_log and restore previous app state
  def process_eventlogs(options = {})
    options[:max_wait_time]               = 20 unless options[:max_wait_time]
    options[:expected_remaining_records]  = 0  unless options[:expected_remaining_records]

    original_worker_threads = MovexCdc::Application.config.initial_worker_threads
    MovexCdc::Application.config.initial_worker_threads = 1                        # Ensure that all keys are matching to this worker thread by MOD

    log_event_logs_content(console_output: false, caption: "#{options[:title]}: Event_Logs records before processing")

    # worker ID=0 for exactly 1 running worker
    worker = TransferThread.new(0, max_transaction_size: 10000)  # Sync. call within one thread

    # Stop process in separate thread after 10 seconds because following call of 'process' will never end without that
    Thread.new do
      loop_count = 0
      while loop_count < options[:max_wait_time] do                           # wait up to x seconds for processing
        loop_count += 1
        event_logs = Database.select_one("SELECT COUNT(*) FROM Event_Logs")
        Rails.logger.debug('ActiveSupport::TestCase.process_eventlogs'){ "#{event_logs} records remaining in Event_Logs" }
        break if event_logs <= options[:expected_remaining_records]           # All records processed, no need to wait anymore
        sleep 1
      end
      worker.stop_thread
    end

    worker.process                                                            # only synchrone execution ensures valid test of function

    remaining_event_log_count = Database.select_one("SELECT COUNT(*) FROM Event_Logs")
    log_event_logs_content(console_output: true, caption: "#{options[:title]}: #{remaining_event_log_count} Event_Logs records after processing") if remaining_event_log_count > options[:expected_remaining_records]   # List remaining events from table

    MovexCdc::Application.config.initial_worker_threads = original_worker_threads  # Restore possibly differing value
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
      assert_equal expected, result, log_on_failure("Expected Statistics value for Table_ID=#{table_id} Name='#{Table.find(table_id).name}', Operation='#{operation}', Column='#{column_name}'")
    else
      assert result >= expected && result <= max_expected, log_on_failure("Statistics value #{result} not between #{expected} and #{max_expected} for Table_ID=#{table_id} Name='#{Table.find(table_id).name}, Operation='#{operation}', Column='#{column_name}'")
    end
  end

  # test for created activity log by previous action ( max. x seconds old)
  def assert_activity_log(user_id: nil, schema_name:nil, table_name:nil, column_name:nil)
    sql = "SELECT COUNT(*) FROM Activity_Logs WHERE Created_At > ".dup
    sql << case MovexCdc::Application.config.db_type
           when 'ORACLE' then ":ts"
           when 'SQLITE' then ":ts"
           end
    sql << " AND "

    where = []
    filter = { ts: Time.now-2}
    if user_id
      where << "user_id = :user_id"
      filter[:user_id]  = user_id
    end
    if schema_name
      where << "schema_name = :schema_name"
      filter[:schema_name] = schema_name
    end
    if table_name
      where << "table_name = :table_name"
      filter[:table_name] = table_name
    end
    if column_name
      where << "column_name = :column_name"
      filter[:column_name] = column_name
    end
    sql << where.join(' AND ')
    Rails.logger.debug('TestHelper.assert_activity_log') { "Max created_at in Activity_Logs is #{Database.select_one("SELECT Max(created_at) FROM Activity_Logs")}"}
    assert Database.select_one(sql, filter) > 0, log_on_failure("Previous operation should have created a record in Activity_Logs for #{filter}")
  end

  # test for created log entry
  # @param [String] expected_log_message
  def assert_log_written(expected_log_message)
    original_logger = Rails.logger
    raise "assert_log_written should be called with a block" unless block_given?
    # Create a log capturing object
    logs = StringIO.new
    Rails.logger = Logger.new(logs)

    yield

    # Check if the log record was written
    assert_includes logs.string, expected_log_message, log_on_failure("Expected log message '#{expected_log_message}' not found in '#{logs.string}'")
  ensure
    Rails.logger = original_logger
  end

end

class ActionDispatch::IntegrationTest
  include TestHelper

  self.use_transactional_tests = false                                        # Like ActiveSupport::TestCase don't rollback transactions
  setup do
    Database.initialize_db_connection                                              # do some init actions for DB connection before use
    GlobalFixtures.initialize_testdata                                                   # Create fixtures only once for whole test, not once per particular test

    # create JWT token for following tests
    @jwt_token                  = jwt_token peter_user.id
    @jwt_admin_token            = jwt_token User.where(email: 'admin').first&.id
    @jwt_no_schema_right_token  = jwt_token User.where(email: 'no_schema_right@xy.com').first&.id
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

class GlobalFixtures

  @@global_fixtures_initialized = false
  def self.initialize_testdata
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
        ColumnExpression.delete_all
        Column.delete_all
        Table.delete_all
        Schema.delete_all

        # load admin from DB each time because ID may change, don't use class User because current_user is not yet defined
        User.new(email: 'admin', db_user: MovexCdc::Application.config.db_user, first_name: 'Admin', last_name: 'from fixture', yn_admin: 'Y').save!
        # User admin can be created without current user set, but from bow it is mandatory
        ApplicationController.set_current_user(User.where(email: 'admin').first) # current user is valid from now
        ApplicationController.set_current_client_ip_info('test-IP')
        @@peter_user = User.new(email: 'Peter.Ramm@og1o.de', db_user: MovexCdc::Application.config.db_victim_user, first_name: 'Peter', last_name: 'Ramm')
        @@peter_user.save!
        @@sandro_user = User.new(email: 'Sandro.Preuss@og1o.de', db_user: MovexCdc::Application.config.db_victim_user, first_name: 'Sandro', last_name: 'Preuß')
        @@sandro_user.save!
        @@no_schema_user = User.new(email: 'no_schema_right@xy.com', db_user: MovexCdc::Application.config.db_victim_user, first_name: 'No', last_name: 'Schema')
        @@no_schema_user.save!

        @@user_schema = Schema.new(name: MovexCdc::Application.config.db_user, topic: KafkaHelper.existing_topic_for_test)
        @@user_schema.save!

        if MovexCdc::Application.config.db_type != 'SQLITE'
          @@victim_schema = Schema.new(name: MovexCdc::Application.config.db_victim_user, topic: KafkaHelper.existing_topic_for_test)
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
                                    topic:      KafkaHelper.existing_topic_for_test,
                                    yn_add_cloudevents_header: 'Y'
        )
        @@victim1_table.save!

        # 5
        @@victim2_table = Table.new(schema_id:  @@victim_schema.id,
                                    name:       'VICTIM2',
                                    info:       'Victim table in separate schema for use with triggers. Contains CLOB column.',
                                    topic:      KafkaHelper.existing_topic_for_test,
                                    yn_add_cloudevents_header: 'N'
        )
        @@victim2_table.save!

        @@victim4_table = Table.new(schema_id:  @@victim_schema.id,
                                    name:       'VICTIM4',
                                    info:       'Victim table in separate schema without primary key constraint.',
                                    topic:      KafkaHelper.existing_topic_for_test
        )
        @@victim4_table.save!

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
                      filter: case MovexCdc::Application.config.db_type
                              when 'ORACLE' then ":new.Name != 'EXCLUDE FILTER'"
                              when 'SQLITE' then "new.Name != 'EXCLUDE FILTER'"
                              end
        ).save!
        Condition.new(table_id: @@victim1_table.id, operation: 'D',
                      filter: case MovexCdc::Application.config.db_type
                              when 'ORACLE' then ":old.ID IS NOT NULL"
                              when 'SQLITE' then "old.ID IS NOT NULL"
                              end
        ).save!

        ColumnExpression.new(table_id: @@victim1_table.id, operation: 'I',
                             sql: case MovexCdc::Application.config.db_type
                                  when 'ORACLE' then
                                    if Database.db_version > '19.1'
                                      "SELECT JSON_OBJECT('Combined' VALUE :new.Name || '-' || :new.num_val) SingleObject FROM DUAL"
                                    else
                                      "SELECT '{\"Combined\":\"' || :new.Name || '-' || :new.num_val || '\"}' SingleObject FROM DUAL"
                                    end
                                  when 'SQLITE' then "SELECT '\"Combined\": \"'||new.name||' - '||new.num_val||'\"'"
                                  end
        ).save!
        ColumnExpression.new(table_id: @@victim1_table.id, operation: 'I',
                             sql: case MovexCdc::Application.config.db_type
                                  when 'ORACLE' then
                                    "SELECT '\"Combined2\":\"' || :new.Name || '-' || :new.num_val || '\"' SingleObject FROM DUAL"
                                  when 'SQLITE' then "SELECT '\"Combined2\": \"'||new.name||' - '||new.num_val||'\"'"
                                  end
        ).save!
        ColumnExpression.new(table_id: @@victim1_table.id, operation: 'U',
                             sql: case MovexCdc::Application.config.db_type
                                  when 'ORACLE' then
                                    if Database.db_version > '19.1'
                                      "SELECT JSON_OBJECT('Combined3' VALUE :new.Name || '-' || :new.num_val) SingleObject FROM DUAL"
                                    else
                                      "SELECT '{\"Combined3\":\"' || :new.Name || '-' || :new.num_val || '\"}' SingleObject FROM DUAL"
                                    end
                                  when 'SQLITE' then "SELECT '\"Combined3\": \"'||new.name||' - '||new.num_val||'\"'"
                                  end
        ).save!
        # Array result for update with multiple rows
        ColumnExpression.new(table_id: @@victim1_table.id, operation: 'U',
                             sql: case MovexCdc::Application.config.db_type
                                  when 'ORACLE' then
                                    if Database.db_version > '19.1'
                                      "SELECT '[ '||LISTAGG(JSON_OBJECT('New_Name' VALUE :new.Name, 'Old_Name' VALUE :old.name), ', ' )||' ]' ArrayList FROM DUAL"
                                    else
                                      # Rel. 12 requires WITHIN GROUP clause and no JSON_OBJECT function
                                      "SELECT '[ '||LISTAGG('{\"New_Name\":\"'||:new.Name||'\", \"Old_Name\": \"'||:old.name||'\"}', ', ') WITHIN GROUP (ORDER BY 1)||' ]' ArrayList FROM DUAL"
                                    end
                                  when 'SQLITE' then "SELECT '\"ArrayList\": [ '||GROUP_CONCAT('{\"New_Name\":\"'||new.name||'\", \"Old_Name\": \"'||old.name||'\"}', ', ') ||' ]'"
                                  end
        ).save!
        ColumnExpression.new(table_id: @@victim1_table.id, operation: 'D',
                             sql: case MovexCdc::Application.config.db_type
                                  when 'ORACLE' then
                                    if Database.db_version > '19.1'
                                      "SELECT JSON_OBJECT('Combined4' VALUE :old.Name || '-' || :old.num_val) SingleObject FROM DUAL"
                                    else
                                      "SELECT '{\"Combined4\":\"' || :old.Name || '-' || :old.num_val || '\"}' SingleObject FROM DUAL"
                                    end
                                  when 'SQLITE' then "SELECT '\"Combined4\": \"'||old.name||' - '||old.num_val||'\"'"
                                  end
        ).save!

        # VICTIM2 should nat have a column expression to test trigger generation without column expressions
        Column.new(table_id: @@victim2_table.id, name: 'ID',          info: 'CLOB test',    yn_log_insert: 'Y', yn_log_update: 'Y', yn_log_delete: 'Y').save!
        Column.new(table_id: @@victim2_table.id, name: 'LARGE_TEXT',  info: 'CLOB test',    yn_log_insert: 'Y', yn_log_update: 'Y', yn_log_delete: 'Y').save!
      ensure
        ApplicationController.unset_current_user
        ApplicationController.unset_current_client_ip_info
      end

      @@victim_connection = case MovexCdc::Application.config.db_type
                            when 'ORACLE' then
                              db_config = Rails.configuration.database_configuration[Rails.env].clone
                              db_config['username'] = MovexCdc::Application.config.db_victim_user
                              db_config['password'] = MovexCdc::Application.config.db_victim_password
                              db_config.symbolize_keys!
                              Rails.logger.debug('GlobalFixtures.initialize'){ "create_victim_connection: creating JDBCConnection" }
                              ActiveRecord::ConnectionAdapters::OracleEnhanced::JDBCConnection.new(db_config)
                            end
      # Fixtures to load only once if successfully initialized
      @@global_fixtures_initialized = true                                      # call only once at start of test suite
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

    if MovexCdc::Application.config.db_type != 'SQLITE'
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

  # Repeat the initialization at start of the next text
  def self.repeat_initialization
    @@global_fixtures_initialized = false
  end

  def self.user_schema;       @@user_schema;        end
  def self.victim_schema;     @@victim_schema;      end
  def self.peter_user;        @@peter_user;         end
  def self.sandro_user;       @@sandro_user;        end
  def self.sandro_user;       @@sandro_user;        end
  def self.tables_table;      @@tables_table;       end
  def self.victim1_table;     @@victim1_table;      end
  def self.victim2_table;     @@victim2_table;      end
  def self.victim4_table;     @@victim4_table;      end

  def self.victim_connection
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      raise "GlobalFixtures.victim_connection not initialized" if !defined?(@@victim_connection) || @@victim_connection.nil?
      @@victim_connection
    when 'SQLITE' then ActiveRecord::Base.connection                            # use currently active connection
    end
  end

  # initialize again after global changes of IDs and content, e.g. from import
  def self.reinitialize
    @@global_fixtures_initialized = false
    self.initialize_testdata
  end

end