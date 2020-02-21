class ExtendUsers2 < ActiveRecord::Migration[6.0]
  def change
    add_index :users, :email,   name: 'IX_USERS_EMAIL',       unique: true,   comment: 'Unique user identifier'
  end
end
