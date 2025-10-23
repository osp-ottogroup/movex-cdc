class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  @@last_job_warnings = {}
  @@reschedule_mutex  = Mutex.new

  # Catch first enqueue to initialize @@last_job_warnings
  after_enqueue do |job|
    if defined?(job.class::CYCLE) && !@@last_job_warnings.has_key?(job.class.name)   # Exclude InitializationJob
      reset_job_warnings(job.class::CYCLE)                                      # init structure at first enqueue per job
    end
  end

  # info for health_check
  # content of @@last_job_warnings should be added with leading line feed
  # !! If jobs are not still alive this should be handled by restart of Docker container after some time of unhealthy container !!
  def self.last_job_warnings
    retval = String.new                                                         # default for :ok

    # Number of cycles to wait before assuming job is not active no more and warning is issued
    wait_factor = 10

    @@last_job_warnings.each do |job_class, job_info|
      retval << job_info[:message] if job_info && !job_info[:message].nil?

      # If job_info is nil, it means that the job has not been enqueued yet
      if job_info && Time.now > job_info[:last_execution] + job_info[:cycle_seconds] * wait_factor
        message = "Last execution of Job #{job_class} (#{job_info[:last_execution]}) is older than now - #{job_info[:cycle_seconds]} seconds "
        message << "(#{job_info[:cycle_seconds]/60} minutes, #{job_info[:cycle_seconds]/3600} hours, #{job_info[:cycle_seconds]/(3600*24)} days ), "
        message << "but should occur every #{job_info[:cycle_seconds]} seconds! Please check for sufficient memory and restart MOVEX CDC to fix the issue."
        Rails.logger.warn('ApplicationJob.last_job_warnings'){ message }

        retval << "\n" if retval != ''
        retval << message
      end
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
