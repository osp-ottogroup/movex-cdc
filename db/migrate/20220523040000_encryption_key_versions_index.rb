class EncryptionKeyVersionsIndex < ActiveRecord::Migration[6.0]

  def up
    add_index :encryption_key_versions, [:encryption_key_id, :version_no], name: 'IX_ENCR_KEY_VERSIONS_UNIQUE', unique: true
  end

  def down
    # oracle_enhanced-apater 6.1.2 throws error:
    # > ArgumentError (No indexes found on statistics with the options provided.)
    # for "change" method if columns are part of remove_index
    # Issue: https://github.com/rsim/oracle-enhanced/issues/2148
    remove_index :encryption_key_versions, name: 'IX_ENCR_KEY_VERSIONS_UNIQUE'
  end
end