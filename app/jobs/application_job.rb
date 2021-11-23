class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  @@last_job_warnings = {}

  # Catch first enqueue to initialize @@last_job_warnings
  after_enqueue do |job|
    if defined?(job.class::CYCLE) && !@@last_job_warnings.has_key?(job.class.name)   # Exclude InitializationJob
      reset_job_warnings(job.class::CYCLE)                                      # init structure at first enqueue per job
    end
  end

  # info for health_check
  # content of @@last_job_warnings should be added with leading line feed
  def self.last_job_warnings(job_class)
    retval = ''                                                                 # default for :ok
    job_info = @@last_job_warnings[job_class.name]

    retval << job_info[:message] if job_info && !job_info[:message].nil?

    if job_info && Time.now > job_info[:last_execution] + job_info[:cycle_seconds]
      retval << "\n" if retval != ''
      retval << "Last execution of Job (#{job_info[:last_execution]}) is older than now - #{job_info[:cycle_seconds]} seconds "
      retval << "(#{job_info[:cycle_seconds]/60} minutes, #{job_info[:cycle_seconds]/3600} hours, #{job_info[:cycle_seconds]/(3600*24)} days ), "
      retval << "but should occure every #{job_info[:cycle_seconds]} seconds"
    end
    retval
  end

  def self.job_infos
    @@last_job_warnings
  end

  def reset_job_warnings(cycle_seconds)
    @@last_job_warnings[self.class.name] ={
      last_execution: Time.now,
      message:        nil,
      cycle_seconds:  cycle_seconds
    }
  end

  def add_execption_to_job_warning(ex)
    @@last_job_warnings[self.class.name][:message] = "\nException: #{ex.class}: #{ex.message}"
  end

end
