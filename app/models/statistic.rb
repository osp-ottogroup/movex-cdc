class Statistic < ApplicationRecord
  belongs_to  :table

  def self.write_record(attribs)
    stat = Statistic.new(attribs.merge({end_timestamp: Time.now}))
    stat.events_success = 0 if stat.events_success.nil?
    stat.events_failure = 0 if stat.events_failure.nil?
    stat.save!
  rescue Exception => e
    ExceptionHelper.log_exception(e, 'Statistic.write_record')                  # No further escalation if write failes
  end

end
