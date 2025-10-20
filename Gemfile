source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

# According to JRuby-Version (movex-cdc/.ruby-version)
#ruby '2.6.8'
#ruby '3.1.0'
# ruby '3.1.4'
ruby '3.4.2'

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
# see: https://rubygems.org/gems/rails/versions
# gem 'rails', '6.1.7.10'
gem 'rails', '8.0.3'

# Use jdbcsqlite3 as the database for gem ctive Record
# gem 'activerecord-jdbcsqlite3-adapter', '~> 80.2'
gem 'activerecord-jdbcsqlite3-adapter', github: 'jruby/activerecord-jdbc-adapter', branch: 'master'

gem "activerecord-oracle_enhanced-adapter", github: 'rammpeter/oracle-enhanced', branch: 'release80'
# gem "activerecord-oracle_enhanced-adapter", github: 'rammpeter/oracle-enhanced', branch: 'release80', ref: 'c1094bc'
# gem 'activerecord-oracle_enhanced-adapter'

# Use Puma as the app server
gem 'puma'

# Use Json Web Token (JWT) for token based authentication
gem 'jwt'

gem 'java-properties'

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin AJAX possible
gem 'rack-cors'

# Avoid error "env: 'jruby_executable_hooks': No such file or directory" at startup in Docker image
#   gem 'executable-hooks'

# Compression tools valid for Kafka
gem 'snappy'
# 'extlz4' and 'zstd-ruby' causes install errors due to missing development tools / not supported by jRuby
# gem 'extlz4'
# gem 'zstd-ruby'

group :development do
  # gem 'listen', '>= 3.0.5', '< 3.2'
  gem 'listen'

  # gem 'rubocop' not really needed as deployment artifact
end

group :test do
  gem 'simplecov', require: false
end

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem 'tzinfo-data', platforms: [:windows, :jruby]
