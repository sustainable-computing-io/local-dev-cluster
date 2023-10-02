#!/bin/bash

# Base directory
BASE_DIR="/sys/devices/virtual/powercap/intel-rapl"

# Find all 'energy_uj' files in directories starting with 'intel-rapl' and change their permissions
find $BASE_DIR -type f -name 'energy_uj' -path "$BASE_DIR/intel-rapl*" -exec sudo chmod a+r {} \;

echo "Permissions updated for all 'energy_uj' files in directories starting with 'intel-rapl*' under $BASE_DIR"

