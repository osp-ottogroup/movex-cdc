require 'thread_handling'

at_exit do
  Rails.logger.warn "Process exit catched by initializers/at_exit, shutting down transfer workers now"
  ThreadHandling.get_instance.shutdown_processing
  Rails.logger.info "MOVEX Change Data Capture: application shutted down now"
end