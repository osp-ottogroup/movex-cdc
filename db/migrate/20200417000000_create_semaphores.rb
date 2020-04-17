class CreateSemaphores < ActiveRecord::Migration[6.0]
  def change
    create_table :semaphores, comment: 'Records to lock at database level as precondition for start of processing' do |t|
      t.string      :process_identifier,  limit: 300,     null: false,  comment: 'Unique identifier of process (hostname + process id)'
      t.integer     :thread_id,           precision: 4,   null: false,  comment: 'ID of transfer thread'
      t.timestamps
    end
  end
end
