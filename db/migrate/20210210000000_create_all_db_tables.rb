class CreateAllDbTables < ActiveRecord::Migration[6.0]
  def up
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      EventLog.connection.execute "\
        CREATE OR REPLACE View All_DB_Tables AS
        SELECT Owner, Table_Name
        FROM   DBA_Tables
        WHERE  Table_Name NOT LIKE 'BIN$%'  /* exclude recycle bin */
        "
    when 'SQLITE' then
      ActiveRecord::Base.connection.execute "DROP VIEW All_DB_Tables" if view_exists? 'All_DB_Tables'
      ActiveRecord::Base.connection.execute "CREATE VIEW All_DB_Tables AS SELECT 'main' Owner, Name Table_Name FROM SQLite_Master WHERE type='table'"
    else
      raise "Declaration for view All_DB_Tables missing for #{Trixx::Application.config.trixx_db_type}"
    end
  end

  def down
    # TODO: view_exists? 'ALL_DB_TABLES' does nor realize existence of view
    ActiveRecord::Base.connection.execute "DROP VIEW All_DB_Tables" if view_exists? 'ALL_DB_TABLES'
  end
end




