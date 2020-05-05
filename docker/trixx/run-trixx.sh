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

export RAILS_LOG_TO_STDOUT=true
export RAILS_SERVE_STATIC_FILES=true
exec rails server --port 8080 --environment production