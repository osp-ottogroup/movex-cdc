require 'thread_handling'

at_exit do
  Rails.logger.warn('initializers/at_exit'){ "Process exit caught, shutting down transfer workers now" }
  ThreadHandling.get_instance.shutdown_processing
  Rails.logger.warn('initializers/at_exit'){ "MOVEX Change Data Capture: application gracefully shut down now" }
end