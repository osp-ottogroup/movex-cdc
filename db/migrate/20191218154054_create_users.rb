class CreateUsers < ActiveRecord::Migration[6.0]

  def up
    # drop potentially existing table. Table may exist without entry in schema_migrations if MOVEX CDC's user hadn't tablespace quota at first try.
    drop_table :users if table_exists? :users                                   # remove table if not registered in schema_migrations

    create_table :users, comment: 'Users allowed to login' do |t|
      t.string  :email,               limit: 256, null: false,  comment: 'Uniqe identifier as login name'
      t.string  :db_user,             limit: 128, null: true,   comment: 'Database user used for authentication combined with password'
      t.string  :first_name,          limit: 128, null: false,  comment: 'First name of user'
      t.string  :last_name,           limit: 128, null: false,  comment: 'Last name of user'
      t.string  :yn_admin,            limit: 1,   null: false,  default: 'N', comment: 'Is user tagged as admin (Y/N)'
      t.string  :yn_account_locked,   limit: 1,   null: false,  default: 'N', comment: 'Is user account locked (Y/N)'
      t.integer :failed_logons,       limit: 2,   null: false,  default: 0,   comment: 'Number of subsequent failed logons'
      t.integer :lock_version,                    null: false,  default: 0,   comment: 'Version for optimistic locking'
      t.string  :yn_hidden,           limit: 1,   null: false,  default: 'N', comment: 'Is user hidden for GUI ? Users are marked hidden instead of physical deletion if they have dependencies.'
      t.timestamps
    end
  end

  def down
    drop_table :users
  end
end
