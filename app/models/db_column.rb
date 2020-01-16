class DbColumn < ApplicationRecord

  # get array of objects with
  def self.all_by_table(schema_name, table_name)
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      ActiveRecord::Base.connection.exec_query("SELECT Column_Name FROM DBA_Tab_Columns WHERE Owner = UPPER(:owner) AND Table_Name = UPPER(:table_name)",
                                               'DbColumn',
                                               [
                                                   ActiveRecord::Relation::QueryAttribute.new(':owner',       schema_name,  ActiveRecord::Type::Value.new),
                                                   ActiveRecord::Relation::QueryAttribute.new(':table_name',  table_name,   ActiveRecord::Type::Value.new)
                                               ]
      )
    when 'SQLITE' then
      result = ActiveRecord::Base.connection.exec_query("SELECT * FROM #{table_name}")
      result.map {|r| { column_name: r}}
    end
  end

end
