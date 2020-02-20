class EventLog < ApplicationRecord
  self.primary_key    = :id                                                     # table does not have real PK constraint
  self.sequence_name  = :event_logs_seq
end
