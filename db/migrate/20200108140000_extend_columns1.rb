class ExtendColumns1 < ActiveRecord::Migration[6.0]
  def change
    add_foreign_key :columns, :tables, name: 'FK_Columns_Tables'
  end
end



