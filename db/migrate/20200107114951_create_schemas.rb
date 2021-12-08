class CreateSchemas < ActiveRecord::Migration[6.0]
  def change
    create_table :schemas, comment: 'Schemas allowed for use with MOVEX CDC by admin acount' do |t|
      t.string    :name,                    limit: 256, null: false,              comment: 'Name of corresponding database schema'
      t.string    :topic,                   limit: 255, null: true,               comment: 'Default topic name for tables of this schema if no topic is defined at table level. Null if topic should be defined at table level'
      t.timestamp :last_trigger_deployment,             null: true,               comment: 'Timestamp of last successful trigger deployment for schema (no matter if there have been changes for triggers or not)'
      t.integer   :lock_version,                        null: false, default: 0,  comment: 'Version for optimistic locking'
      t.timestamps
    end
  end
end
