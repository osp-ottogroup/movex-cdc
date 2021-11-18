class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  @@last_job_warnings = ''

  # info for health_check
  # content of @@last_job_warnings should be added with leading line feed
  def self.last_job_warnings
    @@last_job_warnings != '' ? "#{self.class.name}:#{@@last_job_warnings}" : ''
  end

  def reset_job_warnings
    @@last_job_warnings = ''
  end

  def add_execption_to_job_warning(ex)
    @@last_job_warnings << "\nException: #{ex.class}: #{ex.message}"
  end

end
