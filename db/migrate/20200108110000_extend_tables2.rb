class ExtendTables2 < ActiveRecord::Migration[6.0]
  def change
    add_index :tables, [:schema_id, :name], name: 'IX_TABLES_SCHEMA_NAME', unique: true
  end
end
