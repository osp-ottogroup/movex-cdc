class ExtendSchemaRights2 < ActiveRecord::Migration[6.0]

  def change
    add_foreign_key :schema_rights, :schemas, on_delete: :cascade
  end

end
