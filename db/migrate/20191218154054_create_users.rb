class CreateUsers < ActiveRecord::Migration[6.0]
  def change
    create_table :users do |t|
      t.string :email,        limit: 256, null: false
      t.string :db_user,      limit: 128, null: true
      t.string :first_name,   limit: 128, null: false
      t.string :last_name,    limit: 128, null: false
      t.timestamps
      t.index ["email"],        name: "ix_users_email",     unique: true
      t.index ["db_user"],      name: "ix_users_db_user",   unique: true
    end
  end
end
