class CreateHeartbeats < ActiveRecord::Migration[6.0]
  def change
    create_table :heartbeats, comment: 'Heartbeat of server instance to ensure uniqueness (only one running server allowed)' do |t|
      t.string      :hostname, limit: 1000,  null: false,  comment: 'The host name of the server instance'
      t.string      :ip_address, limit: 100,  null: false, comment: 'The IP address of the server instance as seen by the database'
      t.timestamp   :heartbeat_ts, null: false,  comment: 'The timestamp of the last heartbeat received from the server instance'
    end
  end
end
