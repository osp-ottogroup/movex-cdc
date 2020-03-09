at_exit do
  Rails.logger.info "Process exit catched by initializers/at_exit, shutting down transfer workers now"
  ThreadHandling.get_instance.shutdown_processing
end