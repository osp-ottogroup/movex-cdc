class ExtendTables7 < ActiveRecord::Migration[6.0]
  def change
    add_column :tables, :yn_initialize_with_flashback,  :string, limit: 1, null: false, default: 'Y', comment: 'Should flashback query used to init only records before create trigger SCN'
  end
end
