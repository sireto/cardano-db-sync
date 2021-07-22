#!/usr/bin/env bash
set -eo pipefail

SECRET_DIR=${SECRET_DIR:-/run/secrets}
export PGPASSFILE=${PGPASSFILE:-${SECRET_DIR}/pgpass}
mkdir -p $SECRET_DIR

function getsecret() {
  eval  "VALUE=\$$1"
  FILE="${SECRET_DIR}/$2"
  if [ -z $VALUE ] ; then
    if [ ! -f "$FILE" ] ; then
      echo " Fatal: Required one, missing both \"$1\" and secret file \"$FILE\"" 1>&2
    else
      cat "$FILE"
    fi
  else
    echo "Using environment variable: $1" 1>&2
    echo $VALUE
  fi
}
function param () {
  if [ -n "$2" ] ; then
    echo $1 "$2"
  fi
}

if  [ ! -f "$PGPASSFILE" ] && [ -z $PGPASS ]
then
  POSTGRES_DB="$(getsecret POSTGRES_DB postgres_db)"
  POSTGRES_USER="$(getsecret POSTGRES_USER postgres_user)"
  POSTGRES_PASSWORD="$(getsecret POSTGRES_PASSWORD postgres_password)"
  if [ -z "$POSTGRES_DB" ] || [ -z "$POSTGRES_USER" ] [ -z "$POSTGRES_PASSWORD" ] ; then
  echo  "Exiting due to missing configuration" 2>&2
    exit 1
  fi

 echo  ${POSTGRES_HOST:-postgres}:${POSTGRES_PORT:-5432}:${POSTGRES_DB}:${POSTGRES_USER}:${POSTGRES_PASSWORD} >$PGPASSFILE
cat $PGPASSFILE ; echo
 export PGPASSWORD=$POSTGRES_PASSWORD
 chmod 0600 $PGPASSFILE || echo "Warning couldn't set permission for pgpass file"
 pg_isready -h ${POSTGRES_HOST:-postgres} -p ${POSTGRES_PORT:-5432} -U $POSTGRES_USER -d $POSTGRES_DB
else
	PGPASS=$(getsecret PGPASS pgpass)
	tmp=`cat $PGPASSFILE`
	export PGPASSWORD=${tmp##*:}
  pg_isready  $(param -h $(cut -d : -f1 <<< $PGPASS)) \
    $(param -p $(cut -d : -f2 <<< $PGPASS)) \
    $(param -U $(cut -d : -f4 <<< $PGPASS)) \
    $(param -d $(cut -d : -f3 <<< $PGPASS))
fi

if (( $# > 0 ))
then
  set -x
  exec /bin/cardano-db-sync-extended  "$@"
else
  set -x
  exec /bin/cardano-db-sync-extended  \
  --socket-path /run/cardano-node/node.socket \
  --state-dir /var/lib/cdbsync \
  --schema-dir ./schema \
  --config ./config/mainnet-config.yaml
fi