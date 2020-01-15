class ExtendUsers2 < ActiveRecord::Migration[6.0]
  def change
    add_index :users, :email,   name: "ix_users_email",       unique: true,   comment: 'Unique user identifier'
  end
end
