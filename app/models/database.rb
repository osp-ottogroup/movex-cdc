# Base class for models without DB table but using ActiveRecord::Base
require 'select_hash_helper'
require 'exception_helper'
require 'date'
class Database

  # delegate method calls to DB-specific implementation classes
  @@METHODS_TO_DELEGATE = [
      :set_application_info,
      :db_version,
      :exec_unprepared,
      :jdbc_driver_version,
      :jdbc_driver_path,
      :db_default_timezone,
  ]

  def self.method_missing(method, *args, &block)
    if @@METHODS_TO_DELEGATE.include?(method)
      target_class = case MovexCdc::Application.config.db_type
                     when 'ORACLE' then DatabaseOracle
                     when 'SQLITE' then DatabaseSqlite
                     else
                       raise "Unsupported value for MovexCdc::Application.config.db_type: '#{MovexCdc::Application.config.db_type}'"
                     end
      target_class.send(method, *args, &block)                                         # Call method with same name in target class
    else
      super
    end
  end

  def self.respond_to?(method, include_private = false)
    @@METHODS_TO_DELEGATE.include?(method) || super
  end

  # Initialize and test DB connection
  def self.initialize_db_connection
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      Database.select_one "SELECT SYSDATE FROM DUAL"                            # Check if DB connection is functional
    when 'SQLITE' then
      journal_mode = select_one("PRAGMA journal_mode=WAL")                      # Ensure that concurrent operations are allowed for SQLITE
      Rails.logger.info('Database.initialize_connection'){ "SQLITE journal mode = #{journal_mode}" }
    end

    # used to express the correct DB timezone in event timestamps without transporting it in each Event_logs-record
    unless MovexCdc::Application.config.respond_to?(:db_default_timezone)       # Set only once especially for tests
      MovexCdc::Application.set_and_log_attrib_from_env(:db_default_timezone, default: self.db_default_timezone)
    end

    unless MovexCdc::Application.config.respond_to?(:db_version)                # Set only once especially for tests
      MovexCdc::Application.set_and_log_attrib_from_env(:db_version, default: self.db_version)
    end
    unless MovexCdc::Application.config.respond_to?(:jdbc_driver_version)       # Set only once especially for tests
      MovexCdc::Application.set_and_log_attrib_from_env(:jdbc_driver_version, default: self.jdbc_driver_version)
    end
    unless MovexCdc::Application.config.respond_to?(:jdbc_driver_path) || Rails.env.production?       # Set only once especially for tests
      MovexCdc::Application.set_and_log_attrib_from_env(:jdbc_driver_path, default: self.jdbc_driver_path)
    end
  rescue
    Rails.logger.error('Database.initialize_db_connection') { "Error executing SQL at DB. Connection to DB failed?" }
    raise
  end

  # sample: Database.select_all "SELECT * FROM Table WHERE ID = :id", {id: 55}
  def self.select_all(sql, filter = {})
    raise "Hash expected as filter" if filter.class != Hash

    binds = []
    filter.each do |key, value|
      binds << ActiveRecord::Relation::QueryAttribute.new(key, value, ActiveRecord::Type::Value.new)
    end

    result = ActiveRecord::Base.connection.select_all(sql, "Database.select_all Thread=#{Thread.current.object_id}", binds)
    Rails.logger.debug('Database.select_all'){ "Previous SQL selected #{result.count} records"}
    result.each do |record|
      record.extend TolerantSelectHashHelper
    end
    result
  rescue Exception => e
    ExceptionHelper.log_exception(e, 'Database.select_all', additional_msg: "Erroneous SQL:\n#{sql}\nUsed binds: #{filter}", decorate_additional_message_next_lines: false)
    raise
  end

  def self.select_first_row(sql, filter = {})
    result = select_all(sql, filter)
    return nil if result.count == 0
    result[0]
  end

  # Select a single scalar value from DB
  # @param [String] sql the SQL statement with aliases as :alias
  # @param [Hash] filter the used filters as key/value pairs "alias: value"
  # @return [Any] the selected value
  def self.select_one(sql, filter = {})
    result = select_first_row(sql, filter)
    return nil if result.nil?
    result.first[1]                                                             # Value of Key/Value-Tupels of first element
  end

  # execute SQL with bind variables
  # returns the number of affected rows or 0 for DDL etc.
  # Example: Database.execute("UPDATE Table SET Value=:value", binds: {value: 5})
  def self.execute(sql, binds: {}, options: {})
    raise "Hash expected as binds" if binds.class != Hash

    local_binds = []
    binds.each do |key, value|
      local_binds << ActiveRecord::Relation::QueryAttribute.new(key, value, ActiveRecord::Type::Value.new)
    end

    ActiveRecord::Base.connection.exec_update(sql, "Database.execute", local_binds)  # returns the number of affected rows
  rescue Exception => e
    ExceptionHelper.log_exception(e, 'Database.execute', additional_msg: "Erroneous SQL:\n#{sql}", decorate_additional_message_next_lines:false) unless options[:no_exception_logging]
    raise
  end

  # get SQL expression for current system timestamp from DB
  # @return [String] SQL expression for current system timestamp
  def self.systimestamp_sql
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then "SYSTIMESTAMP"
    when 'SQLITE' then "DATETIME('now')"
    else
      raise "Database.systimestamp: missing value for '#{MovexCdc::Application.config.db_type}'"
    end
  end

  # get current system timestamp from DB
  # @return [Time] current system timestamp
  def self.systime
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then select_one "SELECT SYSTIMESTAMP FROM DUAL"
    when 'SQLITE' then Time.now
    else
      raise "Database.systime: missing value for '#{MovexCdc::Application.config.db_type}'"
    end
  end

  # add DB-specific LIMIT expression
  # @param [String] bind_variable_name
  # @param [Object] sole_filter is there already a WHERE clause in SQL (false) or is limit expression the only filter (true)
  def self.result_limit_expression(bind_variable_name, sole_filter: false)
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then " #{sole_filter ? " WHERE" : " AND"} RowNum <= :#{bind_variable_name}"
    when 'SQLITE' then " LIMIT :#{bind_variable_name}"
    else
      raise "Database.result_limit_expression: missing value for '#{MovexCdc::Application.config.db_type}'"
    end
  end

  # set TCP timeout to ensure canceling of session also if SQL timeout is not working
  def self.set_current_session_network_timeout(timeout_seconds:)
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      raw_conn = ActiveRecord::Base.connection.raw_connection
      # Ensure that hanging SQL executions are cancelled after timeout
      raw_conn.setNetworkTimeout(java.util.concurrent.Executors.newSingleThreadExecutor, timeout_seconds * 1000)
    end
  end

  def self.db_session_info
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      Database.select_one "SELECT SID||','||Serial# FROM v$Session WHERE SID=SYS_CONTEXT('USERENV', 'SID')"
    else '< not implemented >'
    end
  end

  # Ensure that AR connection exists and is valid
  def self.verify_db_connection
    ActiveRecord::Base.connection&.active?                                       # Ensure that connection is established and valid
  rescue Exception => e
    Rails.logger.error('Database.verify_db_connection') { "DB connection lost, try to re-establish it: #{e.class}: #{e.message}" }
    Database.close_db_connection
    raise
  end

  # Physically close the DB connection of the current thread and ensure that the next DB access in that thread will re-open the connection again
  def self.close_db_connection
    ActiveRecord::Base.connection&.throw_away!                                  # Removes the connection from the pool and disconnect it.
  end
end