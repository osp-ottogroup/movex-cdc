class CreateStatistics < ActiveRecord::Migration[6.0]
  def change
    create_table :statistics, comment: 'Throughput statistics' do |t|
      t.references  :table,                         null: false,  comment: 'Reference to table'
      t.string      :operation, limit: 1,           null: false,  comment: 'Operation (I=Insert, U=Update, D=Delete)'
      t.integer     :events_success, precision: 16, null: false,  comment: 'Number of successful processed events'
      t.integer     :events_failure, precision: 16, null: false,  comment: 'Number of event processings ending with failure'
      t.timestamp   :end_timestamp,                 null: false,  comment: 'End of period where events are processed'
    end
  end
end
