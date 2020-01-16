class ExtendSchemaRights1 < ActiveRecord::Migration[6.0]

  def change
    add_foreign_key :schema_rights, :users,   on_delete: :cascade, name: 'FK_Schema_Rights_Users'
  end

end
