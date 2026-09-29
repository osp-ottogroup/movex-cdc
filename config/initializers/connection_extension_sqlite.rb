# Fix Rails 8.1 incompatibility of activerecord-jdbc-adapter (GitHub master, 80.0.pre1) for SQLite
# Rails 8.1 changed the signature of ActiveRecord::ConnectionAdapters::Column#initialize:
#   8.0: Column.new(name, default, sql_type_metadata, null, default_function, ...)
#   8.1: Column.new(name, cast_type, default, sql_type_metadata, null, default_function, ...)
# ArJdbc::SQLite3#new_column_from_field still uses the 8.0 signature, which leads to:
#   NoMethodError: undefined method '=~' for an instance of ActiveRecord::ConnectionAdapters::SqlTypeMetadata
# Remove this patch as soon as activerecord-jdbc-adapter supports Rails 8.1 for SQLite.
if RUBY_ENGINE == 'jruby' && ActiveRecord.version >= Gem::Version.new('8.1')
  require 'arjdbc/sqlite3'

  module ArJdbcSQLite3Rails81ColumnFix
    private

    def new_column_from_field(table_name, field, definitions)
      default         = field["dflt_value"]
      type_metadata   = fetch_type_metadata(field["type"])
      default_value   = extract_value_from_default(default)
      generated_type  = extract_generated_type(field)
      default_function = generated_type.present? ? default : extract_default_function(default_value, default)

      ActiveRecord::ConnectionAdapters::SQLite3Column.new(
        field["name"],
        lookup_cast_type(field["type"]),
        default_value,
        type_metadata,
        field["notnull"].to_i == 0,
        default_function,
        collation:      field["collation"],
        auto_increment: field["auto_increment"],
        rowid:          is_column_the_rowid?(field, definitions),
        generated_type: generated_type
      )
    end
  end

  puts "connection_extension_sqlite.rb: patching SQLite3Adapter#new_column_from_field for Rails 8.1"
  ActiveRecord::ConnectionAdapters::SQLite3Adapter.prepend(ArJdbcSQLite3Rails81ColumnFix)
end

