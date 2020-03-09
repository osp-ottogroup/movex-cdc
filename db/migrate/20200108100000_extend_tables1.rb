class ExtendTables1 < ActiveRecord::Migration[6.0]
  def change
    add_foreign_key :tables, :schemas, name: 'fk_tables_schema'
  end
end
