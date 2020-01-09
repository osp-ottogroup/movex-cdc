class CreateUsers < ActiveRecord::Migration[6.0]
  def change
    create_table :users, comment: 'Users allowed to login' do |t|
      t.string :email,        limit: 256, null: false,  comment: 'Uniqe identifier as login name'
      t.string :db_user,      limit: 128, null: true,   comment: 'Database user used for authentication combined with password'
      t.string :first_name,   limit: 128, null: false,  comment: 'First name of user'
      t.string :last_name,    limit: 128, null: false,  comment: 'Last name of user'
      t.timestamps
      t.index ['email'],        name: "ix_users_email",     unique: true,  comment: 'Unique user identifier'
      t.index ['db_user'],      name: "ix_users_db_user",   unique: false, comment: 'Multiple users may authenticate with same DB-user'
    end
  end
end
