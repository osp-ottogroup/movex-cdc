class ExtendStatistics2 < ActiveRecord::Migration[6.0]
  def up
    add_index :statistics, [:end_timestamp, :table_id, :operation], name: 'IX_STATISTICS_TS_TABLE_ID_OPER'
  end

  def down
    # Rails 6.1.2.1 throws error:
    # > ArgumentError (No indexes found on statistics with the options provided.)
    # for "change" method if columns are part of remove_index
    # remove_index(:statistics, [:end_timestamp, :table_id, :operation], {:name=>"IX_STATISTICS_TS_TABLE_ID_OPER"})
    remove_index :statistics, name: 'IX_STATISTICS_TS_TABLE_ID_OPER'
  end
end


