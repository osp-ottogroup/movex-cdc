class DbColumn < ApplicationRecord
  validates :yn_log_insert, acceptance: { accept: ['Y', 'N'] }
  validates :yn_log_update, acceptance: { accept: ['Y', 'N'] }
  validates :yn_log_delete, acceptance: { accept: ['Y', 'N'] }

  # get array of objects with
  def self.all_by_table(schema_name, table_name)
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      ActiveRecord::Base.connection.exec_query("SELECT Column_Name name FROM DBA_Tab_Columns WHERE Owner = UPPER(:owner) AND Table_Name = UPPER(:table_name)",
                                               'DbColumn',
                                               [
                                                   ActiveRecord::Relation::QueryAttribute.new(':owner',       schema_name,  ActiveRecord::Type::Value.new),
                                                   ActiveRecord::Relation::QueryAttribute.new(':table_name',  table_name,   ActiveRecord::Type::Value.new)
                                               ]
      )
    when 'SQLITE' then
      ActiveRecord::Base.connection.exec_query(
          "SELECT name FROM PRAGMA_TABLE_INFO(:table_name)",
          'DbColumn',
          [
              ActiveRecord::Relation::QueryAttribute.new(':table_name',  table_name,   ActiveRecord::Type::Value.new)
          ]
      )
    end
  end

end
