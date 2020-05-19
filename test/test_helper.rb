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
      exec_db_user_sql("\
        CREATE TRIGGER #{DbTrigger.build_trigger_name(victim1_table.name, victim1_table.id, 'I')} FOR INSERT ON #{victim_schema_prefix}#{victim1_table.name}
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
        CREATE TRIGGER TRIXX_VICTIM1_I INSERT ON #{victim1_table.name}
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

  def create_event_logs_for_test(number_of_records)
    number_of_records.downto(0).each do
      event_log = EventLog.new(table_id: 1, operation: 'I', dbuser: 'Hugo', payload: 'Dummy', created_at: Time.now)
      unless event_log.save
        raise event_log.errors.full_messages
      end
    end
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