class ExtendTables1 < ActiveRecord::Migration[6.0]
  def change
    add_foreign_key :tables, :schemas, name: 'FK_Tables_Schema'
  end
end
