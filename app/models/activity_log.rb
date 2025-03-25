class ActivityLog < ApplicationRecord
  belongs_to :user, optional: true  # optional: true is to avoid the extra lookup on reference for every DML. Integrity is ensured by FK constraint

  # requires successful user login and hash with optional and required keys
  # @param [Hash] activity
  # optional: :schema_name, :table_name, :column_name
  # required: :action
  # @return [void]
  def self.log_activity(activity)
    raise "Missing action for logging" unless activity[:action]

    ActivityLog.new(
      user_id:      ApplicationController.current_user.id,
      schema_name:  activity[:schema_name],
      table_name:   activity[:table_name],
      column_name:  activity[:column_name],
      action:       activity[:action],
      client_ip:    ApplicationController.current_client_ip_info,
      ).save!
  end

end
