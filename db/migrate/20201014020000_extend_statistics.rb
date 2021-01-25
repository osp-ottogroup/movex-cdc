class ExtendStatistics < ActiveRecord::Migration[6.0]
  def change
    add_column :statistics, :events_delayed_errors,  :integer, precision: 16, null: false, default: 0,  comment: 'Number of erroneous single event processings ending in another retry after delay'
    add_column :statistics, :events_final_errors,    :integer, precision: 16, null: false, default: 0,  comment: 'Number of erroneous single event processings ending in final error after retries'
    add_column :statistics, :events_d_and_c_retries, :integer, precision: 16, null: false, default: 0,  comment: 'Number of additional event processings due to divide&conquer retries'
    add_column :statistics, :events_delayed_retries, :integer, precision: 16, null: false, default: 0,  comment: 'Number of additional event processings due to delayed retries'
  end
end