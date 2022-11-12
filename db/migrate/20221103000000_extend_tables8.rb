class ExtendTables8 < ActiveRecord::Migration[6.0]
  def change
    add_column :tables, :yn_add_cloudevents_header,  :string, limit: 1, null: false, default: 'N', comment: 'Should Kafka message headers be added according to CloudEvents standard'
  end
end
