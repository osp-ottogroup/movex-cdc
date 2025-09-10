class SchemasEncryptionKey < ActiveRecord::Migration[6.0]
  def change
    add_reference :schemas, :encryption_key, null:true, foreign_key: {name: "fk_schemas_encryption_key"}, index: {name: 'IX_SCHEMAS_ENCRYPTION_KEY'}
  end
end