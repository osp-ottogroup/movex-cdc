class ExtendConditions3 < ActiveRecord::Migration[6.0]
  def change
    add_index :conditions, [:table_id, :operation], name: 'IX_CONDITIONS_TABLE_ID_OPER', unique: true
  end
end


