class SchemaRight < ApplicationRecord
  belongs_to  :user
  belongs_to  :schema
  validate    :validate_yn_columns

  def validate_yn_columns
    validate_yn_column :yn_deployment_granted
  end

  # user = User
  # user_request_params = [ { :info, schema: { :name }  } ]
  def self.process_user_request(user, user_request_params)
    raise "Array expected for user_request_params" if user_request_params.class != Array

    SchemaRight.where(user_id: user.id).each do |sr|                            # iterate over existing schema_rights of user
      sr.destroy unless user_request_params.map{|r| r[:schema][:name]}.include? sr.schema.name  # remove schema_rights from user that are no more in list
    end

    user_request_params.each do |p|
      schema =  Schema.where(name: p[:schema][:name]).first
      if schema.nil?                                                            # create schema if not already exists
        schema = Schema.new(name: p[:schema][:name])
        schema.save!
      end
      schema_right = SchemaRight.where(user_id: user.id, schema_id: schema.id).first
      if schema_right                                                           # update existing schema_right
        raise "SchemaRight.process_user_request: lock_version is required for schema_right" if p[:lock_version].nil?
        schema_right.update!(info:                  p[:info],
                             yn_deployment_granted: p[:yn_deployment_granted],
                             lock_version:          p[:lock_version]
        )
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

end
