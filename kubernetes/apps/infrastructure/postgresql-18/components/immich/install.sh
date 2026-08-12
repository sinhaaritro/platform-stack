#!/bin/sh
set -e

apt-get update
apt-get install -y ca-certificates wget postgresql-18-pgvector
wget -qO /tmp/vchord.deb https://github.com/supervc-stack/VectorChord/releases/download/1.1.1/postgresql-18-vchord_1.1.1-1_amd64.deb
apt-get install -y /tmp/vchord.deb
rm -f /tmp/vchord.deb

PRELOAD_LIBS="${PRELOAD_LIBS:+$PRELOAD_LIBS,}vchord,vector"