class SchemasEncryptionKey < ActiveRecord::Migration[6.0]
  def change
    add_reference :schemas, :encryption_key, foreign_key: true, null:true
  end
end