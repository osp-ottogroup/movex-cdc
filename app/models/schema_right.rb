class SchemaRight < ApplicationRecord
  belongs_to  :user, optional: true  # optional: true is to avoid the extra lookup on reference for every DML. Integrity is ensured by FK constraint
  belongs_to  :schema, optional: true  # optional: true is to avoid the extra lookup on reference for every DML. Integrity is ensured by FK constraint
  validate    :validate_yn_columns

  def validate_yn_columns
    validate_yn_column :yn_deployment_granted
  end

  # user = User
  # user_request_params = [ { :info, schema: { :name }  } ]
  def self.process_user_request(user, schema_rights_params)
    raise "Array expected for user_request_params" if schema_rights_params.class != Array

    SchemaRight.where(user_id: user.id).each do |sr|                            # iterate over existing schema_rights of user
      sr.destroy unless schema_rights_params.map{|r| r[:schema][:name]}.include? sr.schema.name  # remove schema_rights from user that are no more in list
    end

    schema_rights_params.each do |p|
      schema =  Schema.where(name: p[:schema][:name]).first
      if schema.nil?                                                            # create schema if not already exists
        schema = Schema.new(name: p[:schema][:name])
        schema.save!
      end
      schema_right = SchemaRight.where(user_id: user.id, schema_id: schema.id).first
      if schema_right                                                           # update existing schema_right
        # lock_version is not present in all update cases
        # if a schema right is removed and re-added in the GUI (in the same step in user dialog), it has no lock version
        if p[:lock_version]
          schema_right.update!(info:                  p[:info],
                               yn_deployment_granted: p[:yn_deployment_granted],
                               lock_version:          p[:lock_version]
          )
        else
          schema_right.update!(info:                  p[:info],
                               yn_deployment_granted: p[:yn_deployment_granted]
          )
        end
      else                                                                      # create schema_right if not yet exists
        schema_right = SchemaRight.new(user_id:               user.id,
                                       schema_id:             schema.id,
                                       info:                  p[:info],
                                       yn_deployment_granted: p[:yn_deployment_granted]
        )
        schema_right.save!
      end
    end

  end

  # get hash with schema_name, table_name, column_name for activity_log
  def activity_structure_attributes
    {
      schema_name:  schema.name,
    }
  end
end
