class ExtendStatistics2 < ActiveRecord::Migration[6.0]
  def change
    add_index :statistics, [:end_timestamp, :table_id, :operation], name: 'IX_STATISTICS_TS_TABLE_ID_OPER', unique: false
  end
end


