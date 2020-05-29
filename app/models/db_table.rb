class DbTable < ApplicationRecord

  def self.all_by_schema(schema_name)
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      TableLess.select_all "SELECT Table_Name name FROM DBA_Tables WHERE Owner = UPPER(:schema_name) ORDER BY Table_Name", {schema_name: schema_name}
    when 'SQLITE' then
      TableLess.select_all "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
    end
  end

  def self.remaining_by_schema_id(schema_id)
    schema = Schema.find schema_id
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      TableLess.select_all "SELECT d.Table_Name name
                            FROM   DBA_Tables d
                            WHERE  d.Owner = UPPER(:schema_name)
                            AND    d.Table_Name NOT IN (SELECT Name FROM Tables t WHERE t.Schema_ID = :schema_ID)
                            ORDER BY d.Table_Name", {schema_name: schema.name, schema_id: schema_id}
    when 'SQLITE' then
      TableLess.select_all "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
    end
  end

end
