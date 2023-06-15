require 'rake'
require 'java'

# This Job runs only once at application start
class InitializationJob < ApplicationJob
  queue_as :default

  def perform(*args)
    puts "Initialization at startup\n"
    log_memory_state
    Database.initialize_db_connection                                           # do some init actions for DB connection before use
    ensure_required_rights                                                      # check DB for required rights
    Database.set_application_info('InitializationJob/perform')
    Rails.logger.info('InitializationJob.perform'){ "Start db:migrate to ensure up to date data structures"}
    MovexCdc::Application.load_tasks                                            # precondition for invocation of db:migrate
    if ENV['SUPPRESS_MIGRATION_AT_STARTUP']
      Rails.logger.info('InitializationJob.perform'){ "Migration suppressed because SUPPRESS_MIGRATION_AT_STARTUP is set in environment"}
    else
      Rake::Task['db:migrate'].invoke
    end
    Rails.logger.info('InitializationJob.perform'){ "Finished db:migrate" }

    warmup_ar_classes

    ensure_admin_existence

    # LOG Datase and JDBC driver version
    Rails.logger.info('InitializationJob.perform'){ "JDBC driver version = #{Database.jdbc_driver_version}" }
    MovexCdc::Application.log_attribute('JDBC driver version', Database.jdbc_driver_version)
    Rails.logger.debug('InitializationJob.perform'){ "Database version = #{Database.db_version}"}
    MovexCdc::Application.log_attribute('Database version', Database.db_version)

    EventLog.adjust_interval                                                    # Activate new MovexCdc::Application.config.partition_interval if necessary
    EventLog.adjust_max_simultaneous_transactions                               # Activate new MovexCdc::Application.config.max_simultaneous_transactions if necessary

    # After initialization regular operation can start
    SystemValidationJob.set(wait: 1.seconds).perform_later unless Rails.env.test? # Job is tested separately
    HourlyJob.set(wait: 600.seconds).perform_later unless Rails.env.test?       # Job is tested separately, run first time after SystemValidationJob should have finished
    DailyJob.set(wait: 1200.seconds).perform_later unless Rails.env.test?       # Job is tested separately, run first time after SystemValidationJob should have finished
  rescue Exception => e
    begin
      ExceptionHelper.log_exception(e, 'InitializationJob.perform', additional_msg: "Initialization failed, abort application now!\n#{ExceptionHelper.memory_info_hash}")
    ensure
      exit! 1                                                                   # Ensure application terminates if initialization fails
    end
  end

  private
  # ensure that user admin exists
  def ensure_admin_existence
    admin = User.where(email: 'admin').first
    unless admin
      # create admin user if not yet exists
      ActiveRecord::Base.transaction do
        db_user = case MovexCdc::Application.config.db_type
                  when 'ORACLE' then MovexCdc::Application.config.db_user   # all schemas/users are handled in upper case
                  else
                    MovexCdc::Application.config.db_user
                  end
        user = User.new(email: 'admin', first_name: 'Admin', last_name: 'as Supervisor', db_user: db_user, yn_admin: 'Y')
        user.save!
      end
    end
  end

  # ensure required rights and grants
  def ensure_required_rights
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      check_readable 'DBA_Constraints'
      check_readable 'DBA_Cons_Columns'
      check_readable 'DBA_Role_Privs'
      check_readable 'DBA_Sys_Privs'
      check_readable 'DBA_Tables'
      check_readable 'DBA_Tab_Columns'
      check_readable 'DBA_Tab_Privs'
      check_readable 'GV$Lock'
      check_readable 'V$Database'
      check_readable 'V$Instance'
      check_readable 'V$Session'
    end
    check_create_table
    check_create_view
    check_create_trigger
  end

  # check if read/select is possible on object
  def check_readable(object_name)
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      begin
        Database.select_first_row "SELECT * FROM #{object_name} WHERE RowNum < 2" # read first record of result to ensure access
      rescue Exception => e
        raise "Missing database right???\nSELECT on #{object_name} is not possible!\n#{e.class}: #{e.message}"
      end

      begin
        csql = "CREATE OR REPLACE View MOVEX_CDC_View_Select_Test AS SELECT * FROM #{object_name}"
        Database.execute csql
        Database.execute "DROP View MOVEX_CDC_View_Select_Test"
      rescue Exception => e
        raise "Missing database right???\n#{csql}; is not possible!\n#{e.class}: #{e.message}
You possibly may need a direct GRANT SELECT ON #{object_name} to be enabled to select from table in view"
      end
    end
  end

  # check if create table is possible
  def check_create_table
    begin
      Database.execute "DROP TABLE MOVEX_CDC_Table_Test", options: { no_exception_logging: true}  # drop possibly existing table
    rescue
    end
    Database.execute "CREATE  TABLE MOVEX_CDC_Table_Test (ID NUMBER)"
    Database.execute "DROP TABLE MOVEX_CDC_Table_Test"
  rescue Exception => e
    raise "Missing database right???\nCREATE TABLE is not possible!\n#{e.class}: #{e.message}"
  end

  # check if create view is possible
  def check_create_view
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      Database.execute "CREATE OR REPLACE View MOVEX_CDC_View_Test AS SELECT * FROM DUAL"
      Database.execute "DROP View MOVEX_CDC_View_Test"
    end
  rescue Exception => e
    raise "Missing database right???\nCREATE VIEW is not possible!\n#{e.class}: #{e.message}"
  end

  # Check is user is allowed to create triggers in foreign schemas
  def check_create_trigger
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      priv_count = Database.select_one "SELECT COUNT(*) FROM User_Sys_Privs WHERE UserName = :username AND Privilege = 'CREATE ANY TRIGGER'", username: MovexCdc::Application.config.db_user.upcase
      raise "Missing database right!!! DB user '#{MovexCdc::Application.config.db_user}' lacks the system privilege CREATE ANY TRIGGER" if priv_count == 0
    end
  end

  # Ensure dictionary info for database objects is loaded at startup
  def warmup_ar_classes
    Rails.logger.debug('InitializationJob.warmup_ar_classes'){ "Warmup dictionary info for DB objects started" }
    [ActivityLog, Column, Condition, EventLog, Schema, SchemaRight, Statistic, Table, User].each do |ar_class|
      ar_class.first                                                            # Load one record to provoke loading of dictionary info
    end
    Rails.logger.debug('InitializationJob.warmup_ar_classes'){ "Warmup dictionary info for DB objects finished" }
  end

  def log_memory_state
    Rails.logger.info('InitializationJob.log_memory_state'){ "Memory resources at startup:" }
    ExceptionHelper.memory_info_hash.each do |key, value|
      Rails.logger.info('InitializationJob.log_memory_state'){ "#{value[:name].ljust(25)}: #{value[:value]}" }
    end
  end
end
