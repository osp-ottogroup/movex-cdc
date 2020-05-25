class Statistic < ApplicationRecord
  belongs_to  :table

  def self.write_record(attribs)
    stat = Statistic.new(attribs.merge({end_timestamp: Time.now}))
    stat.events_success = 0 if stat.events_success.nil?
    stat.events_failure = 0 if stat.events_failure.nil?
    stat.save!

    table   = CacheHelper.table_cache(stat.table_id)
    schema  = CacheHelper.schema_cache(table.schema_id)

    # allow transferring log output to time series database
    Rails.logger.info "Statistics: Schema=#{schema.name} Table=#{table.name} Operation=#{KeyHelper.operation_from_short_op(stat.operation)} Events_Success=#{stat.events_success} Events_Failure=#{stat.events_failure}"
  rescue Exception => e
    ExceptionHelper.log_exception(e, 'Statistic.write_record')                  # No further escalation if write failes
  end

  private

end
