class ExtendSchemas1 < ActiveRecord::Migration[6.0]
  def up
    add_index :schemas, :name, name: 'IX_SCHEMAS_NAME',     unique: true, comment: 'Only one record per schema'
  end

  def down
    # oracle_enhanced-apater 6.1.2 throws error:
    # > ArgumentError (No indexes found on statistics with the options provided.)
    # for "change" method if columns are part of remove_index
    # Issue: https://github.com/rsim/oracle-enhanced/issues/2148
    remove_index :schemas, name: 'IX_SCHEMAS_NAME'
  end

end

