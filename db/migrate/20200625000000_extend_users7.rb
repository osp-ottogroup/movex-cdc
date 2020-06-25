class ExtendUsers7 < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :yn_hidden,  :string, limit: 1, null: false, default: 'N', comment: 'Is user hidden for GUI ? Users are marked hidden instead of physical deletion if they have dependencies.'
  end
end