class EventLog < ApplicationRecord
  self.primary_key = "id"                                                       # table does not have real PK constraint
end
