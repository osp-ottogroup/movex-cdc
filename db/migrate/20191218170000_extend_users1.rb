class ExtendUsers1 < ActiveRecord::Migration[6.0]
  def change
    add_index :users, :db_user, name: "ix_users_db_user",     unique: false,  comment: 'Multiple users may authenticate with same DB-user'
  end
end
