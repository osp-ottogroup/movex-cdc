# Activate background-processing for initialization

# Wait async to proceed rails startup before first job execution
InitializationJob.set(wait: 10.seconds).perform_later unless Rails.env.test?    # don't run jobs in test
