class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
  attr_accessor :activity_logged

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
    retval = super
    log_activity('inserted', self.attributes) if retval && new_record
    retval
  end

  def save!(**)
    new_record = new_record?                                                    # call of super toggles the flag
    retval = super
    log_activity('inserted', self.attributes) if new_record
    retval
  end

  def update(attributes)
    retval = super
    log_activity('updated', attributes) if retval
    retval
  end

  def update!(attributes)
    retval = super
    log_activity('updated', attributes)
    retval
  end

  # destroy! itself calles destroy, so one hook is enough
  def destroy
    retval = super
    log_activity('deleted', self.attributes) if retval
    retval
  end


  private
  # ActiveRecord-Classes where DML activities should not be logged
  ACTIVITY_LOG_EXCLUDED_CLASSES=['ActivityLog', 'EventLog', 'Statistic']

  def log_activity(operation, attributes)
    if !ACTIVITY_LOG_EXCLUDED_CLASSES.include?(self.class.name) &&
      !(self.class.name == 'User' && attributes['email'] == 'admin' && operation == 'inserted') # admin user must be created at first without logging
      ActivityLog.log_activity(activity_structure_attributes.merge(action: "#{self.class} #{operation}: #{attributes}"))
    end
  end
end
