# hold open SQL-Cursor and iterate over SQL-result without storing whole result in Array
# Peter Ramm, 02.03.2016

require 'active_record/connection_adapters/abstract_adapter'
require 'active_record/connection_adapters/oracle_enhanced/connection'
require 'active_record/connection_adapters/oracle_enhanced_adapter'
require 'active_record/connection_adapters/oracle_enhanced/quoting'
require 'java'

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
      cursor.get_raw_statement.setFetchSize(5)
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

      Rails.logger.debug "#{row_count} records selected with following SQL"
      cursor.close
      result
    end
  end #iterate_query

end #class_eval

class TableLessOracle
  # options: :query_name, :query_timeout, :fetch_limit
  def self.select_all_limit(stmt, filter={}, options={})
    options[:query_name] = 'select_all_limit' unless options[:query_name]

    raise "Hash expected as filter" if filter.class != Hash
    binds = []
    filter.each do |key, value|
      binds << ActiveRecord::Relation::QueryAttribute.new(key, value, ActiveRecord::Type::Value.new)
    end

    ActiveRecord::Base.connection.get_jdbc_connection.select_all_limit(stmt, binds,options)
  end
end
