class ExtendUsers5 < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :failed_logons, :integer, limit: 2, null: false, default: 0, comment: 'Number of subsequent failed logons'
  end
end
