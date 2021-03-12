class ExtendSchemaRights3 < ActiveRecord::Migration[6.0]

  def up
    add_index :schema_rights, [:user_id, :schema_id], name: 'IX_SCHEMA_RIGHTS_LOGICAL_PKEY', unique: true
  end

  def down
    # oracle_enhanced-apater 6.1.2 throws error:
    # > ArgumentError (No indexes found on statistics with the options provided.)
    # for "change" method if columns are part of remove_index
    # Issue: https://github.com/rsim/oracle-enhanced/issues/2148
    remove_index :schema_rights, name: 'IX_SCHEMA_RIGHTS_LOGICAL_PKEY'
  end

end
