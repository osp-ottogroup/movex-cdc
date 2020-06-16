class CreateUsers < ActiveRecord::Migration[6.0]

  def up
    # drop potentially existing table. Table may exist without entry in schema_migrations if Trixx user hadn't tablespace quota at first try.
    drop_table :users if table_exists? :users                                   # remove table if not registered in schema_migrations

    create_table :users, comment: 'Users allowed to login' do |t|
      t.string :email,        limit: 256, null: false,  comment: 'Uniqe identifier as login name'
      t.string :db_user,      limit: 128, null: true,   comment: 'Database user used for authentication combined with password'
      t.string :first_name,   limit: 128, null: false,  comment: 'First name of user'
      t.string :last_name,    limit: 128, null: false,  comment: 'Last name of user'
      t.timestamps
    end
  end

  def down
    drop_table :users
  end
end
