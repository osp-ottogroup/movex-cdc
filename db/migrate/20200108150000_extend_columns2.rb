class ExtendColumns2 < ActiveRecord::Migration[6.0]
  def change
    add_index :columns, [:table_id, :name], name: 'ix_columns_table_name', unique: true
  end
end



