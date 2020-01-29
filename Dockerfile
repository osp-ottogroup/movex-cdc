FROM jruby:9.2.8.0

WORKDIR /app

COPY Gemfile* ./

RUN bundle install --jobs 4

COPY . .

EXPOSE 3000

CMD rm -f tmp/pids/server.pid && rails server -b 0.0.0.0