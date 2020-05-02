class ExtendTables5 < ActiveRecord::Migration[6.0]
  def change
    add_column :tables, :fixed_message_key,  :string, limit: 255, null: true, comment: 'Fixed value for Kafka message key if kafka_key_handling=F'
  end
end

