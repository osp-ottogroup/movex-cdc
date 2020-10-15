class ReduceStatistics < ActiveRecord::Migration[6.0]
  def change
    remove_column :statistics, :events_failure, :integer
  end
end