class ExtendUsers1 < ActiveRecord::Migration[6.0]
  def up
    add_index :users, :db_user, name: 'IX_USERS_DB_USER',     unique: false,  comment: 'Multiple users may authenticate with same DB-user'
  end

  def down
    # oracle_enhanced-apater 6.1.2 throws error:
    # > ArgumentError (No indexes found on statistics with the options provided.)
    # for "change" method if columns are part of remove_index
    # Issue: https://github.com/rsim/oracle-enhanced/issues/2148
    remove_index :users, name: 'IX_USERS_DB_USER'
  end

end
