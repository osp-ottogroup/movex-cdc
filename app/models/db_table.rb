class DbTable < ApplicationRecord

  # get all tables of schema where the db_user has SELECT grant
  def self.all_by_schema(schema_name, db_user)
    Database.select_all "\
      SELECT Table_Name name
      FROM   Allowed_DB_Tables
      WHERE  Owner   = :owner
      AND    Grantee = :grantee
      ORDER BY Table_Name
      ", {owner: schema_name, grantee: db_user}
  end

=begin
  def self.remaining_by_schema_id(schema_id)
    schema = Schema.find schema_id
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      Database.select_all "SELECT d.Table_Name name
                            FROM   DBA_Tables d
                            WHERE  d.Owner = UPPER(:schema_name)
                            AND    d.Table_Name NOT IN (SELECT Name FROM Tables t WHERE t.Schema_ID = :schema_ID)
                            ORDER BY d.Table_Name", {schema_name: schema.name, schema_id: schema_id}
    when 'SQLITE' then
      Database.select_all "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
    end
  end
=end

end
