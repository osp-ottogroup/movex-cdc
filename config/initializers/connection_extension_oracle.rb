# Extend oracle-enhanced_adapter by some missed features
# Peter Ramm, 2020-12-07
require 'active_record/connection_adapters/oracle_enhanced/connection'
require 'active_record/connection_adapters/oracle_enhanced/jdbc_connection'

ActiveRecord::ConnectionAdapters::OracleEnhanced::JDBCConnection.class_eval do
  alias :org_new_connection :new_connection                                     # remember original implementation

  # Number of SQL cursor to keep open in database even if application closes them after each execution
  JDBC_STATEMENT_CACHE_SIZE = 100

  def new_connection(config)
    raw_connection = org_new_connection(config)                                 # call original implementation first
    Rails.logger.debug('..JDBCConnection.new_connection'){ "Check JDBC implicit statement caching" }

    # Allow Oracle JDBC driver to cache cursors
    unless raw_connection.getImplicitCachingEnabled
      Rails.logger.debug('..JDBCConnection.new_connection'){ "Activate JDBC implicit statement caching" }
      raw_connection.setImplicitCachingEnabled(true)
    end

    # hold up to 100 cursors open
    if raw_connection.getStatementCacheSize != JDBC_STATEMENT_CACHE_SIZE
      Rails.logger.debug('..JDBCConnection.new_connection'){ "Set JDBC implicit statement caching from #{raw_connection.getStatementCacheSize} to #{JDBC_STATEMENT_CACHE_SIZE}" }
      raw_connection.setStatementCacheSize(JDBC_STATEMENT_CACHE_SIZE)
    end

    raw_connection                                                              # return result of original method
  end
end


# Fix for https://github.com/rsim/oracle-enhanced/pull/2473
# https://github.com/rsim/oracle-enhanced/issues/2470

ActiveRecord::ConnectionAdapters::OracleEnhanced::JDBCConnection::Cursor.class_eval do
  puts "connection_extension_oracle.rb: patching OracleEnhanced::JDBCConnection::Cursor to fix issue #2470"
  def select_statement?
    # Only simple SELECT and WITH statements are considered SELECT statements.
    # because no other valid ojdbc method found to check it.

    sql = @raw_statement.get_original_sql.strip

    sql.gsub!(/\A\n+/, "")            # remove leading newlines
    sql.gsub!(/\A\r+/, "")            # remove leading carriage returns
    sql.gsub!(/--.*$/, "")            # remove single line comments
    sql.gsub!(/\/\*.*?\*\//m, "")     # Remove multi-line comments (/* ... */)
    sql.match?(/\A\s*(SELECT|WITH)/i)
  end

end



