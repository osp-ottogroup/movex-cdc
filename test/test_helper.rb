ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'

class ActiveSupport::TestCase
  # Run tests in parallel with specified workers
  # parallel tests deactivated due to database consistency problems, Ramm, 21.12.2019
  # parallelize(workers: :number_of_processors, with: :threads)

  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all

  # Add more helper methods to be used by all tests here...

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
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then connection.exec sql
    when 'SQLITE' then connection.execute sql                                   # standard method for AR.connection
    else
      raise "Unsupported value for Trixx::Application.config.trixx_db_type: '#{Trixx::Application.config.trixx_db_type}'"
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

  def create_victim_structures
    # Renove possible pending structures before recreating
    begin
      drop_victim_structures
    rescue
      nil
    end

    # deactivate column definitions of fixtures in test schema because schemaless DBs create victim tables in same schema
    # This ensures that triggers are generated for victim tables only
    ActiveRecord::Base.connection.execute "\
      UPDATE Columns SET YN_LOG_INSERT='N', YN_LOG_UPDATE='N', YN_LOG_DELETE='N'
      WHERE  Table_ID IN (SELECT ID FROM Tables WHERE UPPER(Name) NOT LIKE 'VICTIM%')
    "

    connection = create_victim_connection
    exec_victim_sql(connection, "CREATE TABLE #{victim_schema_prefix}#{tables(:victim1).name} (ID NUMBER, Name VARCHAR2(20))")

    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      exec_db_user_sql("\
        CREATE TRIGGER TRIXX_VICTIM1_I FOR INSERT ON #{victim_schema_prefix}#{tables(:victim1).name}
        COMPOUND TRIGGER
          BEFORE STATEMENT IS
          BEGIN
            NULL;
          END BEFORE STATEMENT;
        END TRIXX_Victim1_I;
      ")
      exec_db_user_sql("\
        CREATE TRIGGER TRIXX_VICTIM1_TO_DROP FOR UPDATE OF Name ON #{victim_schema_prefix}#{tables(:victim1).name}
        COMPOUND TRIGGER
          BEFORE STATEMENT IS
          BEGIN
            NULL;
          END BEFORE STATEMENT;
        END TRIXX_Victim1_U;
      ")
    when 'SQLITE' then
      exec_db_user_sql("\
        CREATE TRIGGER TRIXX_VICTIM1_I INSERT ON #{tables(:victim1).name}
        BEGIN
          INSERT INTO Event_Logs(Schema_ID, Table_ID, Payload) VALUES (1, 4, '{}');
        END;
      ")
      exec_db_user_sql("\
        CREATE TRIGGER TRIXX_VICTIM1_TO_DROP UPDATE ON #{tables(:victim1).name}
        BEGIN
          INSERT INTO Event_Logs(Schema_ID, Table_ID, Payload) VALUES (1, 4, '{}');
        END;
      ")
    else
      raise "Unsupported value for Trixx::Application.config.trixx_db_type: '#{Trixx::Application.config.trixx_db_type}'"
    end



    logoff_victim_connection(connection)
  end

  def drop_victim_structures
    connection = create_victim_connection
    exec_victim_sql(connection, "DROP TABLE #{victim_schema_prefix}#{tables(:victim1).name}")
    logoff_victim_connection(connection)
  end

end

class ActionDispatch::IntegrationTest
  setup do
    # create JWT token for following tests
    @jwt_token                  = jwt_token users(:one).id
    @jwt_admin_token            = jwt_token users(:admin).id
    @jwt_no_schema_right_token  = jwt_token users(:no_schema_right).id
  end

  def jwt_token(user_id)
    JsonWebToken.encode({user_id: user_id}, 1.hours.from_now)
  end

  # provide JWT token for tests
  def jwt_header(token = @jwt_token)
    { 'Authorization' => token}
  end

end

