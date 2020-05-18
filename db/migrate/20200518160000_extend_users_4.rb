class ExtendUsers4 < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :yn_account_locked, :string, limit: 1, null: false, default: 'N', comment: 'Is user account locked (Y/N)'
  end
end
