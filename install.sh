#!/bin/sh
# File: install.sh
# Author: Malte Harder
# Installs require and reloadable into ~/.julia and juliareq to the binaries
if [ ! -n "$SUDO_USER" ]
then
  HOME=~
  
else
  HOME=$(getent passwd $SUDO_USER | cut -d: -f6)
fi
echo "Installing lib into $HOME/.julia/require"
mkdir -p $HOME/.julia/require
cp src/require.jl $HOME/.julia/require
cp src/reloadable.jl $HOME/.julia/require
echo "Installing juliareq into /usr/bin"
install -t /usr/bin -m 755 src/juliareq