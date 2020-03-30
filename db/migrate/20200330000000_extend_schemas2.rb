class ExtendSchemas2 < ActiveRecord::Migration[6.0]
  def change
    add_column :schemas, :topic, :string, limit: 255, null: true, comment: 'Default topic name for tables of this schema if no topic is defined at table level. Null if topic should be defined at table level'
  end
end

