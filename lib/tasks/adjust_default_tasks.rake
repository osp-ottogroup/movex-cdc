# Remove database tasks for nulldb-adapter
Rake::TaskManager.class_eval do
  def delete_task(task_name)
    @tasks.delete(task_name.to_s)
  end

  if Rails.env.test?
    # Ensure that existing test schema is used instead of schema.rb/structure.sql that regularly recreate schema by db:test:prepare
    Rake.application.delete_task("db:test:load")
    Rake.application.delete_task("db:test:purge")

    msg = "Test-Environment at #{Time.now}:
JAVA_OPTS                 = #{ENV['JAVA_OPTS']}
JRUBY_OPTS                = #{ENV['JRUBY_OPTS']}
    "
    puts msg
  end
end

# Recreate tasks with different content
namespace :db do
  namespace :test do
    task :load do
      puts 'Task db:test:load is removed by lib/tasks/adjust_default_tasks.rake !'
    end
    task :purge do
      puts 'Task db:test:purge removed by lib/tasks/adjust_default_tasks.rake !'
    end
  end

end
