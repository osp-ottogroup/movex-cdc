class IndexHeartbeats < ActiveRecord::Migration[6.0]
  def up
    add_index :heartbeats, [:hostname, :ip_address], name: 'IX_HEARTBEATS_HOSTNAME_IP', unique: true
  end

  def down
    # oracle_enhanced-apater 6.1.2 throws error:
    # > ArgumentError (No indexes found on statistics with the options provided.)
    # for "change" method if columns are part of remove_index
    # Issue: https://github.com/rsim/oracle-enhanced/issues/2148
    remove_index :heartbeats, name: 'IX_HEARTBEATS_HOSTNAME_IP'
  end

end



