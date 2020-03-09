class ExtendConditions1 < ActiveRecord::Migration[6.0]
  def change
    add_foreign_key :conditions, :tables, name: 'fk_conditions_tables'
  end
end


