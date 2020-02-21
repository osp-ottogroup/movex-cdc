class ExtendColumns2 < ActiveRecord::Migration[6.0]
  def change
    add_index :columns, [:table_id, :name], name: 'IX_COLUMNS_TABLE_NAME', unique: true
  end
end



