source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

# According to JRuby-Version (movex-cdc/.ruby-version)
ruby '2.6.8'

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'rails', '6.1.4.1'
# Use jdbcsqlite3 as the database for Active Record
gem 'activerecord-jdbcsqlite3-adapter'
gem 'activerecord-oracle_enhanced-adapter'

# Use Puma as the app server
gem 'puma'

# Use Json Web Token (JWT) for token based authentication
gem 'jwt'

#gem 'ruby-kafka', '1.3.0'
gem 'ruby-kafka', '1.4.0'

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin AJAX possible
gem 'rack-cors'

# Compression tools valid for Kafka
gem 'snappy'
# 'extlz4' and 'zstd-ruby' causes install errors due to missing development tools / not supported by jRuby
# gem 'extlz4'
# gem 'zstd-ruby'

group :development do
  gem 'listen', '>= 3.0.5', '< 3.2'
  # gem 'rubocop' not really needed as deployment artifact
end

group :test do
  gem 'simplecov', require: false
end

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem 'tzinfo-data', platforms: [:mingw, :mswin, :x64_mingw, :jruby]
