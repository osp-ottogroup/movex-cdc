class ExtendSchemaRights4 < ActiveRecord::Migration[6.0]
  def change
    add_column :schema_rights, :yn_deployment_granted, :string,  limit: 1, null: false, default: 'N',  comment: 'Is the user allowed to deploy triggers for this schema?'
  end
end


