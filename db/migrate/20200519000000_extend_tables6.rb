class ExtendTables6 < ActiveRecord::Migration[6.0]
  def change
    add_column :tables, :yn_hidden,  :string, limit: 1, null: false, default: 'N', comment: 'Is table hidden for GUI ? Tables are marked hidden instead of physical deletion.'
  end
end

