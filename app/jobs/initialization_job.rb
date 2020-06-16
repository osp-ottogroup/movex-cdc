require 'rake'

# This Job runs only once at application start
class InitializationJob < ApplicationJob
  queue_as :default

  def perform(*args)
    puts "Initialization at startup"
    Database.set_application_info('InitializationJob/perform')
    Rails.logger.info "Start db:migrate to ensure up to date data structures"
    Trixx::Application.load_tasks
    if ENV['TRIXX_SUPPRESS_MIGRATION_AT_STARTUP']
      Rails.logger.info "Migration suppressed because TRIXX_SUPPRESS_MIGRATION_AT_STARTUP is set in environment"
    else
      Rake::Task['db:migrate'].invoke
    end
    Rails.logger.info "Finished db:migrate"

    ensure_admin_existence

    # LOG JDBC driver version
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then Rails.logger.info "Oracle JDBC driver version = #{ActiveRecord::Base.connection.raw_connection.getMetaData.getDriverVersion}"
    else "JDBC driver version not checked"
    end

    # After initialization regular operation can start
    SystemValidationJob.set(wait: 1.seconds).perform_later unless Rails.env.test? # Job is tested separately
  rescue Exception => e
    begin
      ExceptionHelper.log_exception e, 'Initialization failed, abort application now!'
    ensure
      exit! 1
    end
  end

  # ensure that user admin exists
  def ensure_admin_existence
    admin = User.find_by_email 'admin'
    unless admin
      # create admin user if not yet exists
      ActiveRecord::Base.transaction do
        db_user = case Trixx::Application.config.trixx_db_type
                  when 'ORACLE' then Trixx::Application.config.trixx_db_user   # all schemas/users are handled in upper case
                  else
                    Trixx::Application.config.trixx_db_user
                  end
        user = User.new(email: 'admin', first_name: 'Admin', last_name: 'as Supervisor', db_user: db_user, yn_admin: 'Y')
        user.save!
      end
    end
  end

end
