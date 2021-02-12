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


end
