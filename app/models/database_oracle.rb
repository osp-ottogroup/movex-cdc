# hold open SQL-Cursor and iterate over SQL-result without storing whole result in Array
# Peter Ramm, 02.03.2016

require 'active_record/connection_adapters/abstract_adapter'
require 'active_record/connection_adapters/oracle_enhanced/connection'
require 'active_record/connection_adapters/oracle_enhanced_adapter'
require 'active_record/connection_adapters/oracle_enhanced/quoting'
require 'java'
require 'database'
# get access to private JDBC-Connection
ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.class_eval do
  def get_jdbc_connection
    @connection
  end
end

# Helper-class to allow usage of method "type_cast"
class TypeMapper < ActiveRecord::ConnectionAdapters::AbstractAdapter
  include ActiveRecord::ConnectionAdapters::OracleEnhanced::Quoting
  def initialize                                                                # fake parameter "connection"
    super('Dummy')
  end
end

# expand class by getter to allow access on internal variable @raw_statement
ActiveRecord::ConnectionAdapters::OracleEnhanced::JDBCConnection::Cursor.class_eval do
  def get_raw_statement
    @raw_statement
  end
end

# Class extension by Module-Declaration : module ActiveRecord, module ConnectionAdapters, module OracleEnhancedDatabaseStatements
# does not work as Engine with Winstone application server, therefore hard manipulation of class ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter
# and extension with method iterate_query

ActiveRecord::ConnectionAdapters::OracleEnhanced::JDBCConnection.class_eval do

  def log(sql, name = "SQL", binds = [], type_casted_binds = [], statement_name = '[not defined]')

    name = "#{Time.now.strftime("%H:%M:%S")} #{name}" if Rails.env.test? || Rails.env.development?

    ActiveSupport::Notifications.instrumenter.instrument(
        "sql.active_record",
        :sql                => sql,
        :name               => name,
        :connection_id      => object_id,
        :statement_name     => statement_name,
        :binds              => binds,
        :type_casted_binds  => type_casted_binds
    ) { yield }
  end

  # Method comparable with ActiveRecord::ConnectionAdapters::OracleEnhancedDatabaseStatements.exec_query,
  # but without storing whole result in memory
  # options: :query_name, :query_timeout, :fetch_limit
  def select_all_limit(sql, binds = [], options = {})
    # Variante für Rails 5
    options[:query_name] = 'SQL' unless options[:query_name]

    type_casted_binds = binds.map { |attr| TypeMapper.new.type_cast(attr.value_for_database) }

    query_name = options[:query_name]
    query_name << " fetch_limit=#{options[:fetch_limit]}" if options[:fetch_limit]
    log(sql, query_name, binds, type_casted_binds) do
      cursor = nil
      cursor = prepare(sql)
      cursor.bind_params(type_casted_binds) if !binds.empty?

      cursor.get_raw_statement.setQueryTimeout(options[:query_timeout].to_i) if options[:query_timeout]          # Erweiterunge gegenüber exec_query
      if options[:fetch_limit]
        fetch_size = options[:fetch_limit] < 1000 ? options[:fetch_limit] : 1000    # Limit fetch size
      else
        fetch_size = 100
      end
      cursor.get_raw_statement.setFetchSize(fetch_size)
      cursor.exec

      columns = cursor.get_col_names.map do |col_name|
        # @connection.oracle_downcase(col_name)                               # Rails 5-Variante
        # oracle_downcase(col_name) moved to private _oracle_downcase
        #col_name =~ /[a-z]/ ? col_name : col_name.downcase!
        col_name.downcase!.freeze
      end
      fetch_options = {:get_lob_value => (options[:query_name] != 'Writable Large Object')}
      # noinspection RubyAssignmentExpressionInConditionalInspection
      row_count = 0
      result = []
      while (options[:fetch_limit].nil? || row_count < options[:fetch_limit]) && row = cursor.fetch(fetch_options)
        row_count += 1
        result_hash = {}
        columns.each_index do |index|
          result_hash[columns[index]] = row[index]
          row[index] = row[index].strip if row[index].class == String   # Remove possible 0x00 at end of string, this leads to error in Internet Explorer
        end
        result << result_hash
      end

      Rails.logger.debug('DatabaseOracle.select_all_limit'){ "#{row_count} records selected with following SQL" }
      result
    ensure
      cursor.close if defined?(cursor) && !cursor.nil?
    end
  end #iterate_query

end #class_eval

class DatabaseOracle
  # options: :query_name, :query_timeout, :fetch_limit
  def self.select_all_limit(stmt, filter={}, options={})
    options[:query_name] = 'select_all_limit' unless options[:query_name]

    raise "Hash expected as filter" if filter.class != Hash
    binds = []
    filter.each do |key, value|
      binds << ActiveRecord::Relation::QueryAttribute.new(key, value, ActiveRecord::Type::Value.new)
    end

    ActiveRecord::Base.connection.get_jdbc_connection.select_all_limit(stmt, binds,options)
    # Do not log exception here because it is logged by caller
  rescue Exception => e
    if e.message['ORA-02149'] ||                                                # Specified partition does not exist
      e.message['ORA-08103']  ||                                                # Object No Longer Exists
      e.message['ORA-14766']                                                    # Unable To Obtain A Stable Metadata Snapshot
      Rails.logger.info('DatabaseOracle.select_all_limit'){ "Exception #{e.class}:'#{e.message}' suppressed for SQL:\n#{stmt}" }
      []                                                                        # return empty result and proceed if empty partition has been dropped by housekeeping in the meantime
    else
      ExceptionHelper.log_exception(e, 'DatabaseOracle.select_all_limit',  additional_msg: "Erroneous SQL:\n#{stmt};\nUsed binds: #{filter}") # force exception other than ORA-xxx
      raise
    end
  end

  # Exec SQL with bound list of rowids
  # @param stmt SQL-Statement
  # @param rowid_array Array of rowids
  def self.execute_for_rowid_list(stmt:, rowid_array:, name: "DatabaseOracle.execute_for_rowid_list")
    jdbc_conn = ActiveRecord::Base.connection.raw_connection
    cursor = jdbc_conn.prepareStatement stmt
    ActiveSupport::Notifications.instrumenter.instrument('sql.active_record', sql: stmt, name: name) do
      array = jdbc_conn.createARRAY("#{MovexCdc::Application.config.db_user}.ROWID_TABLE".to_java, rowid_array.to_java);
      cursor.setArray(1, array)
      result = cursor.executeUpdate
      if result != rowid_array.length
        raise "DatabaseOracle.execute_for_rowid_list: Only #{result} records hit instead of #{rowid_array.length}. SQL:\n#{stmt}"
      end
    end
  rescue Exception => e
    ExceptionHelper.log_exception(e, name, additional_msg: "Erroneous SQL:\n#{stmt}")
    raise
  ensure
    cursor.close if defined? cursor && !cursor.nil?
  end

  # Set context info at database session
  def self.set_application_info(action_info)
    sql = "CALL DBMS_APPLICATION_INFO.Set_Module(:module, :action)"
    Database.execute sql, binds: {module: "MOVEX Change Data Capture", action: action_info}
  rescue Exception => e
    ExceptionHelper.log_exception(e, 'DatabaseOracle.set_application_info',  additional_msg: "Erroneous SQL:\n#{sql}")
    # only log exception here if database is not available
    # necessary e.g. for health_check to execute even if DB is not available
  end

  @@cached_db_version = nil
  # Return the DB version as string
  # @return [String] DB version
  def self.db_version
    if @@cached_db_version.nil?
      @@cached_db_version = Database.select_one "SELECT Version FROM v$Instance"
      @@cached_db_version = Database.select_one "SELECT Version_Full FROM v$Instance" if @@cached_db_version >= '19'
    end
    @@cached_db_version
  end

  # Return the JDBC driver version as string
  # @return [String] JDBC driver version
  def self.jdbc_driver_version
    ActiveRecord::Base.connection.raw_connection.getMetaData.getDriverVersion
  end

  # Connect as SYS user to execute SQL statements in rake tasks
  # @return [] JDBC Connection
  def self.connect_as_sys_user
    conn = nil
    raise "Value for DB_SYS_PASSWORD required to create users" if !MovexCdc::Application.config.respond_to?(:db_sys_password)

    db_sys_user = if MovexCdc::Application.config.respond_to?(:db_sys_user)
                    MovexCdc::Application.config.db_sys_user
                  else 'sys'
                  end
    properties = java.util.Properties.new
    properties.put("user", db_sys_user)
    properties.put("password", MovexCdc::Application.config.db_sys_password)
    properties.put("internal_logon", "SYSDBA") if db_sys_user == 'sys'        # admin for autonomous db cannot connect as sysdba
    url = "jdbc:oracle:thin:@#{MovexCdc::Application.config.db_url}"
    begin
      conn = java.sql.DriverManager.getConnection(url, properties)
    rescue
      # bypass DriverManager to work in cases where ojdbc*.jar
      # is added to the load path at runtime and not on the
      # system classpath
      # ORACLE_DRIVER is declared in jdbc_connection.rb of oracle_enhanced-adapter like:
      # ORACLE_DRIVER = Java::oracle.jdbc.OracleDriver.new
      # java.sql.DriverManager.registerDriver ORACLE_DRIVER
      conn = ORACLE_DRIVER.connect(url, properties)
    end
    conn
  end

end
