class CreateTables < ActiveRecord::Migration[6.0]
  def change
    create_table :tables, comment: 'Tables planned for triger creation' do |t|
      t.references  :schema,                            null: false,                comment: 'Reference to schema'
      t.string      :name,                limit: 256,   null: false,                comment: 'Table name of database table'
      t.string      :info,                limit: 1000,  null: true,                 comment: 'Additional info like responsible team'
      t.string      :topic,               limit: 255,   null: true,                 comment: 'Topic name for table. Topic name of schema is used s default if Null'
      t.string      :kafka_key_handling,  limit: 1,     null: false, default: 'N',  comment: 'Type of Kafka key handling for this table. Valid values: N=none, P=primary key, F=fixed value'
      t.string      :fixed_message_key,   limit: 4000,  null: true,                 comment: 'Fixed value for Kafka message key if kafka_key_handling=F'
      t.string      :yn_hidden,           limit: 1,     null: false, default: 'N',  comment: 'Is table hidden for GUI ? Tables are marked hidden instead of physical deletion.'
      t.integer     :lock_version,                      null: false, default: 0,    comment: 'Version for optimistic locking'
      t.timestamps
    end
  end

end
