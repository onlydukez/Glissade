#!/bin/zsh
# Builds and runs the scroll-physics checks. Needs no permissions.
set -e
cd "${0:a:h}"
source ./toolchain.sh
"${SWIFTC[@]}" -O Sources/Core/*.swift Checks/main.swift -o build/checks
./build/checks
