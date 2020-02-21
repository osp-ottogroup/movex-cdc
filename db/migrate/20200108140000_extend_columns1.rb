class ExtendColumns1 < ActiveRecord::Migration[6.0]
  def change
    add_foreign_key :columns, :tables, name: 'fk_columns_tables'
  end
end



