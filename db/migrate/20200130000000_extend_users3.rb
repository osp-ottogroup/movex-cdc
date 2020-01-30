class ExtendUsers3 < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :yn_admin, :string, limit: 1, null: false, default: 'N', comment: 'Is user tagged as admin (Y/N)'
  end
end
