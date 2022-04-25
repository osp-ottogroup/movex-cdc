#!/bin/bash
# start MOVEX CDC application inside a docker container
# Peter Ramm, 2020-03-31

# timezone setting is done by "-e TZ="Europe/Berlin" etc in call of "docker run"

export RAILS_LOG_FILE=log/production.log

echo "Starting MOVEX CDC. Build version is `cat /app/build_version`" | tee -a $RAILS_LOG_FILE

# remove possible remaining PID-File from last run if container did not graceful stop (stop timeout too short)
rm -f tmp/pids/server.pid

export RAILS_LOG_TO_STDOUT_AND_FILE=true
export RAILS_SERVE_STATIC_FILES=true
export RAILS_MIN_THREADS=10
# Default for RAILS_MAX_THREADS is set as ENV in Dockerfile

echo "OS Memory values before starting Rails application:" | tee -a $RAILS_LOG_FILE
function log_memory {
  KEY=$1
  # Log to stdout/Docker log and Rails log
  cat /proc/meminfo 2>/dev/null | grep $KEY | tee -a $RAILS_LOG_FILE
}
log_memory MemTotal
log_memory MemAvailable
log_memory MemFree
log_memory SwapTotal
log_memory SwapFree

# evaluate run config file for settings that should be active at OS level
if [ -n "$RUN_CONFIG" ]
then
  if [ ! -f "$RUN_CONFIG" ]
  then
    echo "Config file '$RUN_CONFIG' pointed to by environment entry RUN_CONFIG is not a valid file"
    ls -l '$RUN_CONFIG'
    exit 1
  fi

  function run_config_value {
    KEY=$1
    # get content before comment marker # and then the field after :
    grep $KEY $RUN_CONFIG | cut -d# -f1 | cut -d: -f2
  }

  CONFIG_RAILS_MAX_THREADS=`run_config_value RAILS_MAX_THREADS`
  if [ -n "$CONFIG_RAILS_MAX_THREADS" ]
  then
    echo "Setting RAILS_MAX_THREADS to $CONFIG_RAILS_MAX_THREADS according to value in config file $RUN_CONFIG" | tee -a $RAILS_LOG_FILE
    export RAILS_MAX_THREADS=$CONFIG_RAILS_MAX_THREADS
  fi

  CONFIG_JAVA_OPTS=`run_config_value JAVA_OPTS`
  if [ -n "$CONFIG_JAVA_OPTS" ]
  then
    if [ -n "$JAVA_OPTS" ]
    then
      echo "Adding JAVA_OPTS '$CONFIG_JAVA_OPTS' to existing environment value '$JAVA_OPTS' according to value in config file $RUN_CONFIG" | tee -a $RAILS_LOG_FILE
      export JAVA_OPTS="$JAVA_OPTS $CONFIG_JAVA_OPTS"
      echo "Resulting value for JAVA_OPTS is '$JAVA_OPTS'" | tee -a $RAILS_LOG_FILE
    else
      echo "Setting JAVA_OPTS to '$CONFIG_JAVA_OPTS' according to value in config file $RUN_CONFIG" | tee -a $RAILS_LOG_FILE
      export JAVA_OPTS="$CONFIG_JAVA_OPTS"
    fi
  fi

  if [ -z "$PUBLIC_PATH" ]; then
    PUBLIC_PATH=`run_config_value PUBLIC_PATH`
  fi
fi

# replace publicPath in VueJS artifacts with empty string for root or additional URL path to use
export PUBLIC_PATH
(
  echo "Replace publicPath / root with '$PUBLIC_PATH'" | tee -a $RAILS_LOG_FILE
  cd public
  # regular hit should be index.html
  sed -i 's/\/REPLACE_PUBLIC_PATH_BEFORE/$PUBLIC_PATH/g' *
  cd js
  sed -i 's/\/REPLACE_PUBLIC_PATH_BEFORE/$PUBLIC_PATH/g' *
)

# Default setting Java heap if not already set by JAVA_OPTS: Set to 75% of available mem
echo $JAVA_OPTS | grep "\-Xmx" >/dev/null
if [ $? -eq 1 ]
then
  typeset -i MEM_AVAIL
  MEM_AVAIL=`cat /proc/meminfo | grep MemAvailable | tr -s ' ' | cut -d' '  -f 2`
  MEM_AVAIL=MEM_AVAIL*75/100/1024
  if [ $MEM_AVAIL -lt 1024 ]
  then
    export JAVA_OPTS="$JAVA_OPTS -Xmx1024m"
    echo "Setting JAVA_OPTS to '$JAVA_OPTS' to ensure at least a minimum of 1GB for max. Java heap size" | tee -a $RAILS_LOG_FILE
    echo "!!! You should increase the available memory for this instance to ensure proper work of MOVEX Change Data Capture !!!" | tee -a $RAILS_LOG_FILE
  else
    export JAVA_OPTS="$JAVA_OPTS -Xmx${MEM_AVAIL}m"
    echo "Setting JAVA_OPTS to '$JAVA_OPTS' to ensure max. Java heap size is 75% of available memory" | tee -a $RAILS_LOG_FILE
  fi
else
  echo "No default setting of Java heap memory because JAVA_OPTS is already set to '$JAVA_OPTS'" | tee -a $RAILS_LOG_FILE
fi

# "exec ..." ensures that rails server runs in the same process like shell script before
# this ensures that MOVEX CDC application is gracefully shut down at docker stop
exec bundle exec rails server --port 8080 --environment production
