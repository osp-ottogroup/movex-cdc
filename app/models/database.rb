# Base class for models without DB table but using ActiveRecord::Base
require 'select_hash_helper'
class Database

  # delegate method calls to DB-specific implementation classes
  @@METHODS_TO_DELEGATE = [
      :set_application_info,
      :db_version,
      :jdbc_driver_version
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

  def self.initialize_connection
    case MovexCdc::Application.config.db_type
    when 'SQLITE' then
      journal_mode = select_one("PRAGMA journal_mode=WAL")                      # Ensure that concurrent operations are allowed for SQLITE
      Rails.logger.info('Database.initialize_connection'){ "SQLITE journal mode = #{journal_mode}" }
    end
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
    ExceptionHelper.log_exception(e, 'Database.select_all', additional_msg: "Erroneous SQL:\n#{sql}")
    raise
  end

  def self.select_first_row(sql, filter = {})
    result = select_all(sql, filter)
    return nil if result.count == 0
    result[0]
  end

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

    ActiveRecord::Base.connection.exec_update(sql, "Database.execute Thread=#{Thread.current.object_id}", local_binds)  # returns the number of affected rows
  rescue Exception => e
    ExceptionHelper.log_exception(e, 'Database.execute', additional_msg: "Erroneous SQL:\n#{sql}") unless options[:no_exception_logging]
    raise
  end

  # get SQL expression for current system timestamp from DB
  def self.systimestamp
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then "SYSTIMESTAMP"
    when 'SQLITE' then "DATETIME('now')"
    else
      raise "Database.systimestamp: missing value for '#{MovexCdc::Application.config.db_type}'"
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

end