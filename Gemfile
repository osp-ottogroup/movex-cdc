source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

# According to JRuby-Version (trixx/.ruby-version)
ruby '2.5.8'

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'rails', '6.1.3.1'
# Use jdbcsqlite3 as the database for Active Record
gem 'activerecord-jdbcsqlite3-adapter'
gem 'activerecord-oracle_enhanced-adapter'

# TODO: 1.8.8 leads to error: NoMethodError (undefined method `deep_merge!' for {}:Concurrent::Hash
gem 'i18n', '1.8.7'


# Use Puma as the app server
gem 'puma'
# Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
# gem 'jbuilder', '~> 2.7'

# Use Json Web Token (JWT) for token based authentication
gem 'jwt'
# Use Active Model has_secure_password
# gem 'bcrypt', '~> 3.1.7'

gem 'ruby-kafka', '1.3.0'

# Use Active Storage variant
# gem 'image_processing', '~> 1.2'

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
