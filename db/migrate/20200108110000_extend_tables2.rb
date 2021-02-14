class ExtendTables2 < ActiveRecord::Migration[6.0]
  def up
    add_index :tables, [:schema_id, :name], name: 'IX_TABLES_SCHEMA_NAME', unique: true
  end

  def down
    # oracle_enhanced-apater 6.1.2 throws error:
    # > ArgumentError (No indexes found on statistics with the options provided.)
    # for "change" method if columns are part of remove_index
    # Issue: https://github.com/rsim/oracle-enhanced/issues/2148
    remove_index :tables, name: 'IX_TABLES_SCHEMA_NAME'
  end

end
