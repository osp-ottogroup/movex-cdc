class ExtendSchemaRights1 < ActiveRecord::Migration[6.0]

  def change
    add_foreign_key :schema_rights, :users,   on_delete: :cascade, name: 'fk_schema_rights_users'
  end

end
