#!/bin/bash
# start MOVEX CDC application inside a docker container
# Peter Ramm, 2020-03-31

# timezone setting is done by "-e TZ="Europe/Berlin" etc in call of "docker run"

echo "MOVEX CDC build version is `cat /app/build_version`"

# remove possible remaining PID-File from last run if container did not graceful stop (stop timeout too short)
rm -f tmp/pids/server.pid

export RAILS_LOG_TO_STDOUT_AND_FILE=true
export RAILS_SERVE_STATIC_FILES=true
export RAILS_MIN_THREADS=10
# Default for RAILS_MAX_THREADS is set as ENV in Dockerfile

# "exec ..." ensures that rails server runs in the same process like shell script before
# this ensures that MOVEX CDC application is gracefully shut down at docker stop
exec bundle exec rails server --port 8080 --environment production
