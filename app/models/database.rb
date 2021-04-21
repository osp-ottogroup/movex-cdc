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
      target_class = case Trixx::Application.config.trixx_db_type
                     when 'ORACLE' then DatabaseOracle
                     when 'SQLITE' then DatabaseSqlite
                     else
                       raise "Unsupported value for Trixx::Application.config.trixx_db_type: '#{Trixx::Application.config.trixx_db_type}'"
                     end
      target_class.send(method, *args, &block)                                         # Call method with same name in target class
    else
      super
    end
  end

  def self.respond_to?(method, include_private = false)
    @@METHODS_TO_DELEGATE.include?(method) || super
  end


  def self.select_all(sql, filter = {})
    raise "Hash expected as filter" if filter.class != Hash

    binds = []
    filter.each do |key, value|
      binds << ActiveRecord::Relation::QueryAttribute.new(key, value, ActiveRecord::Type::Value.new)
    end

    result = ActiveRecord::Base.connection.select_all(sql, "Database.select_all Thread=#{Thread.current.object_id}", binds)
    result.each do |record|
      record.extend TolerantSelectHashHelper
    end
    result
  rescue Exception => e
    ExceptionHelper.log_exception(e, "Database.select_all: Erroneous SQL:\n#{sql}")
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
  # Example: Database.execute("UPDATE Table SET Value=:value", {value: 5})
  def self.execute(sql, filter = {}, options = {})
    raise "Hash expected as filter" if filter.class != Hash

    binds = []
    filter.each do |key, value|
      binds << ActiveRecord::Relation::QueryAttribute.new(key, value, ActiveRecord::Type::Value.new)
    end

    ActiveRecord::Base.connection.exec_update(sql, "Database.execute Thread=#{Thread.current.object_id}", binds)  # returns the number of affected rows
  rescue Exception => e
    ExceptionHelper.log_exception(e, "Database.execute: Erroneous SQL:\n#{sql}") unless options[:no_exception_logging]
    raise
  end

  # get SQL expression for current system timestamp from DB
  def self.systimestamp
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then "SYSTIMESTAMP"
    when 'SQLITE' then "DATETIME('now')"
    else
      raise "Database.systimestamp: missing value for '#{Trixx::Application.config.trixx_db_type}'"
    end
  end

  def self.result_limit_expression(bind_variable_name, sole_filter: false)
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then " #{sole_filter ? " WHERE" : " AND"} RowNum <= :#{bind_variable_name}"
    when 'SQLITE' then " LIMIT :#{bind_variable_name}"
    else
      raise "Database.result_limit_expression: missing value for '#{Trixx::Application.config.trixx_db_type}'"
    end
  end

  # set TCP timeout to ensure canceling of session also if SQL timeout is not working
  def self.set_current_session_network_timeout(timeout_seconds:)
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      raw_conn = ActiveRecord::Base.connection.raw_connection
      # Ensure that hanging SQL executions are cancelled after timeout
      raw_conn.setNetworkTimeout(java.util.concurrent.Executors.newSingleThreadExecutor, timeout_seconds * 1000)
    end
  end

  def self.db_session_info
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      Database.select_one "SELECT SID||','||Serial# FROM v$Session WHERE SID=SYS_CONTEXT('USERENV', 'SID')"
    else '< not implemented >'
    end
  end

end