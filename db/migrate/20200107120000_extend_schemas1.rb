class ExtendSchemas1 < ActiveRecord::Migration[6.0]
  def change
    add_index :schemas, :name, name: 'IX_SCHEMAS_NAME',     unique: true, comment: 'Only one record per schema'
  end
end

