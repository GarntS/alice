#!/bin/sh
export LD_LIBRARY_PATH=/usr/lib/alicebar/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
exec /usr/lib/alicebar/alicebar "$@"
