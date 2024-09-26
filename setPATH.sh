#!/bin/bash

# Script to make all scripts and modules accessible by setting PATH
# Copyright (C) 2024  Paul Meiners
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  See https://www.gnu.org/licenses/ if not.

# Determine directory where this script is located
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Array of directories for PATH
PATH_DIRS=(
    "${BASE_DIR}"
#   "${BASE_DIR}/subdirectory"
)

# Add directories to PATH
for extra in "${PATH_DIRS[@]}"; do
    if [[ ":$PATH:" != *":$extra:"* ]]; then
        export PATH="$PATH:$extra"
    fi
done

# # Array of directories for PYTHONPATH
# PYTHONPATH_DIRS=(
#     "${BASE_DIR}"
# #   "${BASE_DIR}/subdirectory"
# )

# # Add directories to PYTHONPATH
# for extra in "${PYTHONPATH_DIRS[@]}"; do
#     if [[ ":$PYTHONPATH:" != *":$extra:"* ]]; then
#         export PYTHONPATH="$PYTHONPATH:$extra"
#     fi
# done

# Clean up variables
unset BASE_DIR
