class Statistic < ApplicationRecord
  belongs_to  :table

  def self.write_record(attribs)
    stat = Statistic.new(attribs.merge({end_timestamp: Time.now}))
    stat.save!
  rescue Exception => e
    ExceptionHelper.log_exception(e, 'Statistic.write_record')                  # No further escalation if write failes
  end

  private

end
