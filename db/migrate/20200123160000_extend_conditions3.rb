class ExtendConditions3 < ActiveRecord::Migration[6.0]
  def up
    add_index :conditions, [:table_id, :operation], name: 'IX_CONDITIONS_TABLE_ID_OPER', unique: true
  end

  def down
    # Rails 6.1.2.1 throws error:
    # > ArgumentError (No indexes found on statistics with the options provided.)
    # for "change" method if columns are part of remove_index
    remove_index :conditions, name: 'IX_CONDITIONS_TABLE_ID_OPER'
  end
end


