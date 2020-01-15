class ExtendColumns1 < ActiveRecord::Migration[6.0]
  def change
    add_foreign_key :columns, :tables
  end
end



