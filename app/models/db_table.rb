class DbTable < ApplicationRecord

  # get all tables of schema where the db_user has SELECT grant
  def self.all_by_schema(schema_name, db_user)
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      #TableLess.select_all "SELECT Table_Name name FROM DBA_Tables WHERE Owner = UPPER(:schema_name) ORDER BY Table_Name", {schema_name: schema_name}
      db_user_up = db_user.upcase
      TableLess.select_all "\
        SELECT Table_Name Name FROM DBA_Tables WHERE Owner = :db_user1 AND Owner = :schema_name1 /* Own schema has tables */
        UNION
        /* Explicite table grants for user */
        SELECT Table_Name
        FROM   DBA_TAB_PRIVS
        WHERE  Privilege = 'SELECT'
        AND    Type = 'TABLE'
        AND    Owner = :schema_name2
        AND    Grantee = :db_user2
        UNION
        /* All schemas with tables if user has SELECT ANY TABLE */
        SELECT Table_Name FROM DBA_Tables WHERE Owner = :schema_name3 AND EXISTS (SELECT 1 FROM DBA_Sys_Privs WHERE Privilege = 'SELECT ANY TABLE' AND Grantee = :db_user3)
      ", {db_user1: db_user_up, schema_name1: schema_name, schema_name2: schema_name, db_user2: db_user_up, schema_name3: schema_name, db_user3: db_user_up}

    when 'SQLITE' then
      TableLess.select_all "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
    end
  end

=begin
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
=end

end
