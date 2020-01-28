class ExtendTables2 < ActiveRecord::Migration[6.0]
  def change
    add_index :tables, [:schema_id, :name], name: 'ix_tables_schema_name', unique: true
  end
end
