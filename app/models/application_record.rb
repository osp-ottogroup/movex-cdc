class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
  attr_accessor :original_attributes

  # Ensure column contains Y or N
  # @param [Symbol] column_name column name to check
  def validate_yn_column(column_name)
    if send(column_name) != 'Y' && send(column_name) != 'N'
      errors.add(column_name, "Column '#{column_name}' should contain 'Y' or 'N' but not '#{send(column_name)}'")
    end
  end

  # get hash with schema_name, table_name, column_name
  def activity_structure_attributes
    raise "Abstract method activity_structure_attributes should be overloaded in class #{self.class}"
  end

  def save(**)
    new_record = new_record?                                                    # call of super toggles the flag
    changed = changed?                                                          # changed? only valid before excution of super
    retval = super
    log_activity('inserted', self.attributes) if retval && new_record
    log_activity('updated', self.changes) if retval && !new_record && changed
    retval
  rescue Exception => e
    Rails.logger.error('ApplicationRecord.save') { "#{e.message}, attributes: #{self.attributes}" }
    raise
  end

  def save!(**)
    new_record = new_record?                                                    # call of super toggles the flag
    changed = changed?                                                          # changed? only valid before excution of super
    retval = super
    log_activity('inserted', self.attributes) if new_record
    log_activity('updated', self.changes) if !new_record && changed
    retval
  rescue Exception => e
    Rails.logger.error('ApplicationRecord.save!') { "#{e.message}, attributes: #{self.attributes}" }
    raise
  end

  def update(attributes)
    super
  rescue Exception => e
    Rails.logger.error('ApplicationRecord.update') { "#{e.message}, attributes: #{self.attributes}" }
    raise
  end

  def update!(attributes)
    super
  rescue Exception => e
    Rails.logger.error('ApplicationRecord.update!') { "#{e.message}, attributes: #{self.attributes}" }
    raise
  end

  # destroy! itself calls destroy, so one hook is enough
  def destroy
    retval = super
    log_activity('deleted', self.attributes) if retval
    retval
  rescue Exception => e
    Rails.logger.error('ApplicationRecord.destroy') { "#{e.message}, attributes: #{self.attributes}" }
    raise
  end


  private
  # ActiveRecord-Classes where DML activities should not be logged
  ACTIVITY_LOG_EXCLUDED_CLASSES=['ActivityLog', 'EventLog', 'Statistic']

  # wtite activity log entry
  # @param [String] operation 'inserted', 'updated', 'deleted'
  # @param [Hash] attributes attributes of the record
  # @return [void]
  def log_activity(operation, attributes)
    if !ACTIVITY_LOG_EXCLUDED_CLASSES.include?(self.class.name) &&
      !(self.class.name == 'User' && attributes['email'] == 'admin' && operation == 'inserted') # admin user must be created at first without logging
      ActivityLog.log_activity(activity_structure_attributes.merge(action: "#{self.class} #{operation}: #{attributes}"))
    end
  end
end
