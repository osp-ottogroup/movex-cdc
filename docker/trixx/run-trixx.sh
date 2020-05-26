#!/bin/bash
# start TriXX application inside a docker container
# Peter Ramm, 2020-03-31

# set timezone if requested like TIMEZONE="Europe/Berlin"
if [ -n "$TIMEZONE" ]; then
  echo "Setting timezone to $TIMEZONE"
  echo $TIMEZONE > /etc/timezone
  rm /etc/localtime && ln -s /usr/share/zoneinfo/$TIMEZONE /etc/localtime
  dpkg-reconfigure -f noninteractive tzdata
fi

echo "TriXX build version is `cat /app/build_version`"

export RAILS_LOG_TO_STDOUT_AND_FILE=true
export RAILS_SERVE_STATIC_FILES=true
export RAILS_MIN_THREADS=10
if [ -z "$RAILS_MAX_THREADS" ]; then
  export RAILS_MAX_THREADS=300
fi
exec rails server --port 8080 --environment production