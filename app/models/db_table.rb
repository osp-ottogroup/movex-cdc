class DbTable < ApplicationRecord

  def self.all_by_schema(schema_name)
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      ActiveRecord::Base.connection.exec_query("SELECT Table_Name name FROM DBA_Tables WHERE Owner = UPPER(:A1)", 'DbTable',  [ActiveRecord::Relation::QueryAttribute.new(':A1', schema_name, ActiveRecord::Type::Value.new)])
    when 'SQLITE' then
      ActiveRecord::Base.connection.exec_query("SELECT name FROM sqlite_master WHERE type='table'")
    end
  end

end
