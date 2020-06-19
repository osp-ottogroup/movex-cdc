class ExtendUsers6 < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :lock_version, :integer, null: false, default: 0, comment: 'Version for optimistic locking'
  end
end