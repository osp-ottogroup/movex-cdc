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
  def self.last_job_warnings(job_class)
    retval = ''                                                                 # default for :ok
    job_info = @@last_job_warnings[job_class.name]

    retval << job_info[:message] if job_info && !job_info[:message].nil?

    if job_info && Time.now > job_info[:last_execution] + job_info[:cycle_seconds]
      retval << "\n" if retval != ''
      retval << "Last execution of Job #{job_class} (#{job_info[:last_execution]}) is older than now - #{job_info[:cycle_seconds]} seconds "
      retval << "(#{job_info[:cycle_seconds]/60} minutes, #{job_info[:cycle_seconds]/3600} hours, #{job_info[:cycle_seconds]/(3600*24)} days ), "
      retval << "but should occure every #{job_info[:cycle_seconds]} seconds! Please check for sufficient memory and restart MOVEX CDC to fix the issue."
    end
    retval
  end

  # Sometimes at OutOfMemory conditions jobs are not restarted and remain inactive for the future
  # Housekeeping executed by Docker container can repair this seldom scenario
  def self.ensure_job_rescheduling
    if @@reschedule_mutex.locked?
      Rails.logger.warn('ApplicationJob.ensure_job_restarts'){"Mutex is locked by another thread. Not waiting."}
      return                                                                    # do not wait for mutex in health_check
    end
    @@reschedule_mutex.synchronize do
      wait_factor = 2                                                             # reschedule jobs if not executed within twice the expected cycle
      @@last_job_warnings.each do |job_class_name, value|
        if Time.now > value[:last_execution] + value[:cycle_seconds] * wait_factor    # Wait twice the cycle before assuming job as not active no more
          SystemValidationJob.set(wait: CYCLE.seconds).perform_later unless Rails.env.test?  # Ensure next execution independent from following operations
          Rails.logger.warn('ApplicationJob.ensure_job_restarts'){ "Job '#{job_class_name}' has not been executed for #{wait_factor} * cycle_seconds (#{value[:cycle_seconds]})!"}
          Rails.logger.warn('ApplicationJob.ensure_job_restarts'){ "Last execution time for job '#{job_class_name}' was #{value[:last_execution]}."}
          Rails.logger.warn('ApplicationJob.ensure_job_restarts'){ "This may happen randomly if application runs out of memory."}
          Rails.logger.warn('ApplicationJob.ensure_job_restarts'){ "Rescheduling job '#{job_class_name}' for now + #{value[:cycle_seconds]} seconds."}
          job_class_name.constantize.set(wait: value[:cycle_seconds].seconds).perform_later # unless Rails.env.test?
        end
      end
    end
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
