# Extend oracle-enhanced_adapter by some missed features
# Peter Ramm, 2020-12-07
require 'active_record/connection_adapters/oracle_enhanced/connection'
require 'active_record/connection_adapters/oracle_enhanced/jdbc_connection'

ActiveRecord::ConnectionAdapters::OracleEnhanced::JDBCConnection.class_eval do
  alias :org_new_connection :new_connection                                     # remember original implementation

  # Number of SQL cursor to keep open in database even if application closes them after each execution
  JDBC_STATEMENT_CACHE_SIZE = 50

  def new_connection(config)
    raw_connection = org_new_connection(config)                                 # call original implementation first
    Rails.logger.debug('..JDBCConnection.new_connection'){ "Check JDBC implicit statement caching" }

    # Allow Oracle JDBC driver to cache cursors
    unless raw_connection.getImplicitCachingEnabled
      Rails.logger.debug('..JDBCConnection.new_connection'){ "Activate JDBC implicit statement caching" }
      raw_connection.setImplicitCachingEnabled(true)
    end

    # hold up to x cursors open
    if raw_connection.getStatementCacheSize != JDBC_STATEMENT_CACHE_SIZE
      Rails.logger.debug('..JDBCConnection.new_connection'){ "Set JDBC implicit statement caching from #{raw_connection.getStatementCacheSize} to #{JDBC_STATEMENT_CACHE_SIZE}" }
      raw_connection.setStatementCacheSize(JDBC_STATEMENT_CACHE_SIZE)
    end

    if !Rails.env.production?
      begin
        statement = raw_connection.createStatement
        statement.executeUpdate("ALTER SESSION SET Statistics_Level = ALL")
        Rails.logger.debug('..JDBCConnection.new_connection'){ "Oracle session statistics level set to ALL" }
      rescue Exception => e
        Rails.logger.error('..JDBCConnection.new_connection'){ "Unable to set Oracle session statistics level to ALL: #{e.message}" }
      ensure
        statement.close if statement
      end
    end

    raw_connection                                                              # return result of original method
  rescue Exception => e
    ExceptionHelper.log_exception(e, 'JDBCConnection.new_connection', additional_msg: "Error establishing connection to DB", decorate_additional_message_next_lines: false)
    raise
  end

  # Workaround for issue #2476 (method reset missing)
  def reset
    reset!
  rescue Exception => e
    ExceptionHelper.log_exception(e, 'JDBCConnection.reset', additional_msg: "Error resetting connection to DB", decorate_additional_message_next_lines: false)
    raise
  end

  def connect
    new_connection(@config)
  end
end


# The former patch of Cursor#select_statement? for https://github.com/rsim/oracle-enhanced/issues/2470 has been removed:
# oracle-enhanced 8.1 checks for an existing result set now, and the patch (using get_original_sql) fails for plain Statements.

# Fix for oracle-enhanced 8.1.x: JDBCConnection#prepare uses a plain java.sql.Statement (createStatement) for SQL starting
# with CREATE|DROP|BEGIN|DECLARE and stores the SQL in @exec_sql. Cursor#exec respects this, but Cursor#exec_update doesn't
# and calls executeUpdate without SQL, which leads to:
#   ArgumentError: no method 'executeUpdate' (for zero arguments) on Java::OracleJdbcDriver::OracleStatementWrapper
# Affects e.g. Database.execute "BEGIN ... END;" or Database.execute "DROP TRIGGER ..." without bind variables.
# Remove this patch as soon as oracle-enhanced fixes Cursor#exec_update.
ActiveRecord::ConnectionAdapters::OracleEnhanced::JDBCConnection::Cursor.class_eval do
  puts "connection_extension_oracle.rb: patching OracleEnhanced::JDBCConnection::Cursor#exec_update for DDL and PL/SQL without binds"
  def exec_update
    @exec_sql ? @raw_statement.executeUpdate(@exec_sql) : @raw_statement.executeUpdate  # @exec_sql is nil for PreparedStatement
  end

end



