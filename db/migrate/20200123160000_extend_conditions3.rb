class ExtendConditions3 < ActiveRecord::Migration[6.0]
  def change
    add_index :conditions, [:table_id, :operation], name: 'IX_Conditions_Table_ID_Operation', unique: true
  end
end


