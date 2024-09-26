#!/bin/bash

# Script to collect thermodynamic information from ORCA output files
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

# Function to show help message
show_help() {
    echo -e "\n\n    Utilization: $(basename "$0") <ORCA_output_file>"
    echo -e "\n    This script takes an ORCA output file and extracts thermodynamic information"
    echo -e "    including vibrational frequencies, final single point and Gibbs free energies.\n\n"
}

# Display help message
case "$1" in
    "" | "-h" | "--help") show_help; exit 0 ;;
esac

# Path of ORCA output file
input_file="$1"

# Validate ORCA output file
if [ ! -f "${input_file}" ]; then
    echo -e "\n  Error: ORCA output file '${input_file}' does not exist.\n"
    exit 1
elif ! grep -q "\* O   R   C   A \*" "${input_file}"; then
    echo -e "\n  Error: '${input_file}' is not a valid ORCA output file.\n"
    exit 1
fi

# Check ORCA termination status
if ! grep -q "ORCA TERMINATED NORMALLY" "${input_file}"; then
    echo -e "\n  Error: ORCA did not terminate normally.\n"
    exit 1
elif grep -q -e "ERROR" -e "aborting the run" "${input_file}"; then
    echo -e "\n  Error: ORCA terminated with an error.\n"
    exit 1
fi

# Flag to check if any data is found
thermo_found=0

# Look for last frequency block
last_block=$(awk '
    /VIBRATIONAL FREQUENCIES/ { block = ""; in_block = 1; next }
    /NORMAL MODES/ { if (in_block) { last_block = block; in_block = 0 } next }
    in_block { block = (block ? block "\n" : "") $0 }
    END { print last_block }
' "${input_file}")

# Check if a frequency block exists
if [ -n "${last_block}" ]; then
    thermo_found=1 # Set flag for thermodynamic data

    # Check for imaginary frequencies
    imaginary_mode=$(echo "${last_block}" | awk '
        /\*\*\*imaginary mode\*\*\*/ {
            match($0, /([0-9]+):[ ]*([+-]?[0-9]*\.?[0-9]+)/, arr)
            printf "%15d:%11.2f cm**-1\n", arr[1], arr[2]
        }
    ')

    # Check for very small frequencies
    small_frequency=$(echo "${last_block}" | awk '
        /^[ ]*[0-9]+:[ ]+([0-9]*\.?[0-9]+) cm\*\*-1/ {
            if ($2 > 0 && $2 <= 15) {
                match($0, /([0-9]+):[ ]*([+-]?[0-9]*\.?[0-9]+)/, arr)
                printf "%16d:%11.2f cm**-1\n", arr[1], arr[2]
            }
        }
    ')

    # Output imaginary and very small frequencies
    if [ -z "${imaginary_mode}" ]; then
        echo -e "\n  No imaginary frequencies."
    else
        echo -e "\n  Warning: Imaginary mode(s)$(echo "${imaginary_mode}" | sed '1!s/^/                            /')"
    fi

    if [ -n "${small_frequency}" ]; then
        echo -e "\n  Caution: Very low mode(s)$(echo "${small_frequency}" | sed '1!s/^/                           /')"
    fi
fi

# Extract final values
final_spe=$(awk '
    /FINAL SINGLE POINT ENERGY/ {
        match($0, /FINAL SINGLE POINT ENERGY[ ]*([-+]?[0-9]*\.?[0-9]+)/, arr)
        if (arr[1] != "") {
            final_spe = arr[1];
        }
    }
    END {
        if (final_spe != "") {
            printf "  Final single point energy%32.12f Eh\n", final_spe;
        }
    }
' "${input_file}")

final_g=$(awk '
    /Final Gibbs free energy/ {
        match($0, /Final Gibbs free energy[^-]*([-+]?[0-9]*\.?[0-9]+)[ ]*Eh/, arr)
        if (arr[1] != "") {
            final_g = arr[1];
        }
    }
    END {
        if (final_g != "") {
            printf "  Final Gibbs free energy%30.8f     Eh\n", final_g;
        }
    }
' "${input_file}")

g_eel=$(awk '
    /G-E\(el\)/ {
        match($0, /G-E\(el\)[^0-9]*([+-]?[0-9]*\.?[0-9]+)[ ]*Eh/, arr)
        if (arr[1] != "") {
            g_eel = arr[1];
        }
    }
    END {
        if (g_eel != "") {
            printf "  For completeness G-E(el)%29.8f     Eh\n", g_eel;
        }
    }
' "${input_file}")

# Check if any thermodynamic values were found
if [ -n "${final_spe}" ] || [ -n "${final_g}" ] || [ -n "${g_eel}" ]; then
    thermo_found=1  # Set flag for thermodynamic data
fi

# Error if no thermodynamic information was found
if [ "${thermo_found}" -eq 0 ]; then
    echo -e "\n  Error: No thermodynamic information found in output file.\n"
    exit 1
fi

# Print extracted values if available
if [ -n "${final_spe}" ]; then
    echo -e "\n${final_spe}"
fi

if [ -n "${final_g}" ]; then
    echo "${final_g}"
fi

if [ -n "${g_eel}" ]; then
    echo "${g_eel}"
fi

echo
