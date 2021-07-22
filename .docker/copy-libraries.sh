#!/bin/bash

### Author: github.com/mesudip
###
### After cabal build is executed, this script searches the required executables,
### find their shared library dependencies and creates a directory `chroot-env` with it.
### The directory is self sufficient for running the executable with chroot but configuration files
### will have to be copied for it to properly work.
###
set -eo pipefail

WORKDIR=$(readlink -f ./chroot-env)
echo "Creating chroot environment on ./chroot-env"
mkdir -p "$WORKDIR/bin"
mkdir -p "$WORKDIR/usr/bin"

# given a filename copy it to ./chroot-env
# also find the libraries it depends on and copy them.
function copyExecutable(){
  local FILE=$1
  echo "Copying  $(basename $FILE)"
  cp -u --preserve=timestamps,mode "$FILE" "$WORKDIR${2:-/bin}"

  echo "Collecting the shared library dependencies for $(basename $FILE)..."
  deps=$(ldd $FILE | awk 'BEGIN{ORS=" "}$EXECUTABLE\
  ~/^\//{print $1}$3~/^\//{print $3}'\
   | sed 's/,$/\n/')

  set "$(ldd $FILE  | grep ld-linux)"
  if [ -f "$1" ]
  then
    echo "Copying $1"
    mkdir -p "$WORKDIR$(dirname $1)"
    cp -u --preserve=timestamps,mode $1 "$WORKDIR$1"
  fi
  $D

  #Copy the deps
  for dep in $deps
  do
        echo "Copying $dep"
        mkdir -p "$WORKDIR$(dirname $dep)"
        cp -u --preserve=timestamps,mode "$dep" "$WORKDIR$dep"
  done
}
function findExecutable() {
  find 'dist-newstyle/build' -type f -name "$1" | grep "$(getVersion $1)"
}
function getVersion(){
  grep -i '^version' ./$1/$1.cabal  | grep -Eo '[[:digit:]]+(\.[[:digit:]]+)*'
}

#Get the library dependencies
copyExecutable "$(findExecutable cardano-db-sync-extended)"
copyExecutable "$(findExecutable cardano-db-sync)"
copyExecutable "$(findExecutable cardano-db-tool)"
copyExecutable /bin/bash
copyExecutable /bin/ls
copyExecutable /bin/sh
copyExecutable /bin/cat
copyExecutable /usr/bin/printenv

echo "Done"
