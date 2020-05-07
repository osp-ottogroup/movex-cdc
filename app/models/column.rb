class Column < ApplicationRecord
  belongs_to :table
  attribute :yn_pending, :string, limit: 1, default: 'N'  # is changed column value waiting for being activated in new generated trigger

  def self.count_active(filter_hash)
    retval = 0
    Column.where(filter_hash).each do |c|
      retval +=1 if c.yn_log_insert == 'Y' || c.yn_log_update == 'Y' || c.yn_log_delete == 'Y'
    end
    retval
  end

  def as_json(*args)
    calc_yn_pending                                                             # Calculate pending state before returning values to GUI
    super.as_json(*args)
  end

  private
  # set yn_pending to 'Y' if change is younger than last trigger generation check
  def calc_yn_pending
    last_trigger_deployment = table.schema.last_trigger_deployment
    self.yn_pending = last_trigger_deployment.nil? || last_trigger_deployment < updated_at ? 'Y' : 'N'
  end
end
