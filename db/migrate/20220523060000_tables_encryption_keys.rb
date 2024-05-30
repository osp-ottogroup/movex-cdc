class TablesEncryptionKeys < ActiveRecord::Migration[6.0]
  def change
    add_reference :tables, :encryption_key, foreign_key: true, null:true
  end
end