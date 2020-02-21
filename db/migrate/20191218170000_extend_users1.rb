class ExtendUsers1 < ActiveRecord::Migration[6.0]
  def change
    add_index :users, :db_user, name: 'IX_USERS_DB_USER',     unique: false,  comment: 'Multiple users may authenticate with same DB-user'
  end
end
