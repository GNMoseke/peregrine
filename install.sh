#!/bin/sh
echo "Building peregrine with swift version $(swift --version)"
swift build -c release
cp .build/release/peregrine /usr/local/bin/

