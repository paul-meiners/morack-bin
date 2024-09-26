#!/bin/bash

# Script to create .xyz file from SMILES string on bwForCluster JUSTUS 2
# Copyright (C) 2024  Paul Meiners, Tobias Morack
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

# Function to display help message
usage() {
    echo -e "\n\n    BASH script to generate an xTB optimized .xyz file from a SMILES string on bwForCluster JUSTUS 2"
    echo -e "\n    Utilization: $(basename "$0") [Options] \"SMILES\""
    echo -e "\n    Description:"
    echo "      This script generates a 3D molecular structure from a given SMILES string using the chemical toolbox"
    echo "      OpenBabel, and then optimizes the initial guess using the semiempirical quantum chemistry program xTB."
    echo -e "\n    Options:"
    echo "      -c charge             Set the molecular charge for geometry optimization with xTB (default: 0)."
    echo "      -m multiplicity       Set the spin multiplicity for geometry optimization with xTB (default: 1)."
    echo "      -o output filename    Set the output filename without extension (default: current directory name)."
    echo "      -t opt threshold      Set the threshold for geometry optimization with xTB (default: tight),"
    echo "                                the Options are crude, sloppy, loose, lax, normal, tight, vtight, extreme."
    echo "      -v verbose output     Print module output to screen, this flag requires no argument (default: off)."
    echo "      -l keep output log    Keep logged module output, this flag requires no argument (default: off)."
    echo "      -f keep all files     Keep all intermediate files, this flag requires no argument (default: off)."
    echo "      -s submit job         Submit job to SLURM scheduler, this flag requires no argument (default: off)."
    echo -e "\n    Argument: \"SMILES\"      The SMILES string in quotation marks, representing the structure to be created."
    echo -e "\n    IMPORTANT NOTICE:"
    echo "      Do not forget to first request an interactive job like this 'salloc --nodes=1 --ntasks-per-node=4' or"
    echo -e "      submit to the SLURM scheduler. Running this script on a login node may result in policy violations.\n\n"
}

# Default parameters
chrg=0          # Charge (default: 0)
mult=1          # Multiplicity (default: 1)
out_name=$(basename "$PWD")  # Output filename (default: current directory name)
thresh="tight"  # Optimization threshold for xTB (default: tight)
verbose=0       # Verbose flag (default: 0 - do not print output to screen)
keep_log=0      # Keep logged output (default: 0 - delete)
keep_all=0      # Keep all intermediate files (default: 0 - delete)
submit_job=0    # SLURM submission flag (default: 0 - do not submit)
error_flag=0    # Flag to indicate if any error occurred
exit_status=0   # Initialize flag for exit status of this script
temp_dir_created=0  # Flag to indicate if temporary directory was created

# Function to parse and validate command-line arguments
get_args() {
    while getopts ':c:m:o:t:vlfsh' flag; do
        case $flag in
            c)
                if [[ $OPTARG =~ ^[+-]?[0-9]+$ ]]; then
                    chrg=${OPTARG// /}
                else
                    echo -e "\n  Error: Invalid value '$OPTARG' for charge. Must be an integer with optional sign.\n"
                    exit 1
                fi
                ;;
            m)
                if [[ $OPTARG =~ ^[1-9][0-9]*$ ]]; then
                    mult=$OPTARG
                else
                    echo -e "\n  Error: Invalid value '$OPTARG' for multiplicity. Must be a positive integer greater than zero.\n"
                    exit 1
                fi
                ;;
            o)
                out_name=$OPTARG
                ;;
            t)
                case $OPTARG in
                    crude|sloppy|loose|lax|normal|tight|vtight|extreme)
                        thresh=$OPTARG
                        ;;
                    *)
                        echo -e "\n  Error: Invalid optimization threshold. Must be one of crude, sloppy, loose, lax, normal, tight, vtight, or extreme.\n"
                        exit 1
                        ;;
                esac
                ;;
            v)
                verbose=1
                ;;
            l)
                keep_log=1
                ;;
            f)
                keep_all=1
                ;;
            s)
                submit_job=1
                ;;
            h)
                usage
                exit 0
                ;;
            \?)
                echo -e "\n  Error: Invalid option '-$OPTARG'. Check documentation for details.\n"
                exit 1
                ;;
            :)
                echo -e "\n  Error: Option '-$OPTARG' requires an argument.\n"
                exit 1
                ;;
        esac
    done

    shift $((OPTIND - 1))
    smiles="$1"

    # Check if SMILES string is provided and not empty
    if [ -z "$smiles" ]; then
        echo -e "\n  Error: SMILES string in quotation marks not provided.\n"
        exit 1
    fi
}

# Function to create a SLURM submission script
create_slurm_script() {
slurm_script="${out_name}.sh"
cat << EOF > "${slurm_script}"
#!/bin/bash

########## BEGIN QUEUEING SYSTEM JOB PARAMETERS ################################
#
#SBATCH --job-name=${out_name}
#SBATCH --output=%x.%j.log
#SBATCH --error=%x.%j.log
#SBATCH --time=00:10:00
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=4
#SBATCH --mem-per-cpu=2000
#
########## END QUEUEING SYSTEM JOB PARAMETERS ##################################

cleanup() {
    if [ "${keep_all}" -eq 1 ]; then
        echo -e "\n\n### Copying tgz-archive of results to SLURM_SUBMIT_DIR..."
        echo; mkdir -vp "\${SLURM_SUBMIT_DIR}" # If submit directory has been deleted or moved
        echo "Creating result tgz-file '\${SLURM_SUBMIT_DIR}/\${JOB_WORK_DIR}.tgz'..."
        echo; cd "\${TMP_BASE_DIR}"
        tar -zcvf "\${SLURM_SUBMIT_DIR}/\${JOB_WORK_DIR}.tgz" "\${JOB_WORK_DIR}"
    elif [ -e "${out_name}.xyz" ] || [ "${keep_log}" -eq 1 ] && [ -e "${out_name}.out" ]; then
        echo -e "\n\n### Copying results to SLURM_SUBMIT_DIR..."
        echo; mkdir -vp "\${SLURM_SUBMIT_DIR}" # If submit directory has been deleted or moved
        if [ -e "${out_name}.xyz" ]; then
            cp -v "${out_name}.xyz" "\${SLURM_SUBMIT_DIR}"
        fi
        if [ "${keep_log}" -eq 1 ] && [ -e "${out_name}.out" ]; then
            cp -v "${out_name}.out" "\${SLURM_SUBMIT_DIR}"
        fi
    fi

    echo -e "\n\n### Removing TMP_WORK_DIR..."
    echo; rm -rvf "\${TMP_WORK_DIR}"

    end=\$(date +%s)

    echo -e "\n\n### Calculating duration..."
    echo -e "\nEND_TIME = \`date +'%Y-%m-%d %H:%M:%S'\`"
    diff=\$[end-start]
    if [ \$diff -lt 60 ]; then
        echo -e "\nRuntime (approx.): '\$diff' secs"
    elif [ \$diff -ge 60 ]; then
        echo -e "\nRuntime (approx.): '\$[\$diff / 60]' min(s) '\$[\$diff % 60]' secs"
    fi

    echo -e "\n\n### Exiting with exit code..."
    echo -e "\nJob exit-code: \${exit_status}"
    echo; exit \${exit_status}
}


start=\$(date +%s)


echo -e "\n### Setting up shell environment and defaults for environment vars..."
# Reset all language and locale dependencies (write floats with a dot "."):
unset LANG; export LC_ALL="C"
# Define fallbacks and "sanitize" important environment variables:
export USER="\${USER:=\`logname\`}"
export SLURM_JOB_ID="\${SLURM_JOB_ID:=\`date +%s\`}"
export SLURM_SUBMIT_DIR="\${SLURM_SUBMIT_DIR:=\`pwd\`}"
export SLURM_JOB_NAME="\${SLURM_JOB_NAME:=\`basename "\$0"\`}"
export SLURM_JOB_NAME="\${SLURM_JOB_NAME//[^a-zA-Z0-9._-]/_}"
export SLURM_JOB_NUM_NODES="\${SLURM_JOB_NUM_NODES:=1}"
export SLURM_CPUS_ON_NODE="\${SLURM_CPUS_ON_NODE:=1}"
export SLURM_NTASKS="\${SLURM_NTASKS:=1}"


echo -e "\n\n### Printing basic job infos to stdout..."

echo -e "\nSTART_TIME          = \`date +'%Y-%m-%d %H:%M:%S'\`"
echo "HOSTNAME            = \${HOSTNAME}"
echo "USER                = \${USER}"
echo "SLURM_JOB_NAME      = \${SLURM_JOB_NAME}"
echo "SLURM_JOB_ID        = \${SLURM_JOB_ID}"
echo "SLURM_SUBMIT_DIR    = \${SLURM_SUBMIT_DIR}"
echo "SLURM_JOB_NUM_NODES = \${SLURM_JOB_NUM_NODES}"
echo "SLURM_CPUS_ON_NODE  = \${SLURM_CPUS_ON_NODE}"
echo "SLURM_NTASKS        = \${SLURM_NTASKS}"
echo "SLURM_JOB_NODELIST  = \${SLURM_JOB_NODELIST}"
echo "---------------- ulimit -a -S ----------------"
ulimit -a -S
echo "---------------- ulimit -a -H ----------------"
ulimit -a -H
echo "----------------------------------------------"


# --- Setting up working directory --- #

echo -e "\n\n### Creating TMP_WORK_DIR directory and changing to it..."
echo; if test -z "\$SLURM_JOB_NUM_NODES" -o "\$SLURM_JOB_NUM_NODES" = "1"; then
    if test -n "\${SCRATCH}" -a -e "\${SCRATCH}" -a -d "\${SCRATCH}" -a "\${SCRATCH}" != "/scratch" -a "\${SCRATCH}" != "/tmp" -a "\${SCRATCH}" != "/ramdisk"; then
        TMP_BASE_DIR="\${SCRATCH:=/tmp/\${USER}}"
    else
        TMP_BASE_DIR="\${TMPDIR:=/tmp/\${USER}}"
    fi
else
    TMP_BASE_DIR="\${SCRATCH:=/tmp/\${USER}}"
fi

JOB_WORK_DIR="\${SLURM_JOB_NAME}.\${SLURM_JOB_ID%%.*}"
TMP_WORK_DIR="\${TMP_BASE_DIR}/\${JOB_WORK_DIR}"
echo "TMP_BASE_DIR = \${TMP_BASE_DIR}"
echo "JOB_WORK_DIR = \${JOB_WORK_DIR}"
echo "TMP_WORK_DIR = \${TMP_WORK_DIR}"

if test "\${SLURM_JOB_NUM_NODES:-1}" -gt 1 -a -n "\$SLURM_JOB_NODELIST" -a "\$TMP_BASE_DIR" != "\$SLURM_SUBMIT_DIR"
then
    for host in \$(scontrol show hostnames "\$SLURM_JOB_NODELIST")
    do
        echo -e "\nmkdir \${TMP_WORK_DIR} on \${host}"
        ssh "\$host" mkdir -vp \${TMP_WORK_DIR}
    done
else
    echo -e "\nmkdir \${TMP_WORK_DIR} on \${HOSTNAME}"
    mkdir -vp \${TMP_WORK_DIR}
fi
echo; mkdir -vp \${TMP_WORK_DIR}


# --------- Running the job ----------- #

echo -e "\n### Loading software modules..."
cd "\${TMP_WORK_DIR}"
module --quiet purge
module --quiet load chem/openbabel
OBABEL_VERSION=\$(module list 2>&1 | grep 'chem/openbabel' | sed -n 's/.*chem\/openbabel\/\([^ ]*\).*/\1/p')
if [ -z "\$OBABEL_VERSION" ]; then
    echo "ERROR: Failed to load 'chem/openbabel' module."
    exit 101
fi
echo -e "\nOBABEL_VERSION = \$OBABEL_VERSION"
module --quiet load chem/xtb
if [ -z "\$XTB_VERSION" ]; then
    echo "ERROR: Failed to load 'chem/xtb' module."
    exit 101
fi
echo "XTB_VERSION    = \$XTB_VERSION"
module list


echo "### Displaying internal xTB environments..."

echo -e "\nXTB_BIN_DIR = \${XTB_BIN_DIR}"
echo "XTB_EXA_DIR = \${XTB_EXA_DIR}"
echo "XTB_VERSION = \${XTB_VERSION}"

# Set up xTB with useful machine settings
export MKL_NUM_THREADS=4
export OMP_NUM_THREADS=4,1
export OMP_MAX_ACTIVE_LEVELS=1
export OMP_STACKSIZE=2G

# Avoid stack overflows by uncapping system stack
ulimit -s unlimited


echo -e "\n\n### Running the job..."

echo -e "\nJob starts on \$HOSTNAME in \$(pwd) with SMILES string: '$smiles'"

{ echo -e "\n                           *****************"; echo "                           * smiles2xyz.sh *"; echo "                           *****************"; } >> "${out_name}.out"

echo -e "\nGenerating 3D molecular structure using OpenBabel..." | tee -a "${out_name}.out"
if ! obabel -:"$smiles" -oxyz -O "obabel.xyz" --gen3d --better >> "${out_name}.out" 2>&1; then
    echo "Error: OpenBabel failed to generate initial guess." | tee -a "${out_name}.out"
    exit_status=1; cleanup
fi
if [ ! -s "obabel.xyz" ]; then
    echo "Error: Output file 'obabel.xyz' not created by OpenBabel." | tee -a "${out_name}.out"
    exit_status=1; cleanup
fi

echo "Optimizing initial guess 'obabel.xyz' using xTB..." | tee >(sed '1i\'$'\n' >> "${out_name}.out")
if ! xtb "obabel.xyz" --chrg "$chrg" --uhf "$(( mult - 1 ))" --opt "$thresh" >> "${out_name}.out" 2>&1; then
    echo "Error: xTB geometry optimization failed." | tee -a "${out_name}.out"
    exit_status=1; cleanup
fi
if [ ! -s "xtbopt.xyz" ]; then
    echo "Error: Output file 'xtbopt.xyz' not created by xTB." | tee -a "${out_name}.out"
    exit_status=1; cleanup
fi

echo "Adding SMILES string to 'xtbopt.xyz' comment line and renaming output..." | tee >(sed '1i\'$'\n' >> "${out_name}.out")
awk -v smiles="$smiles" 'NR==2 {print \$0 " SMILES: " smiles} NR!=2' "xtbopt.xyz" > "${out_name}.xyz"
if [ ! -f "${out_name}.xyz" ]; then
    echo "Error: Final output file '${out_name}.xyz' not created." | tee -a "${out_name}.out"
    exit_status=1; cleanup
fi

echo -e "\nFinal output file '${out_name}.xyz' created successfully." | tee -a "${out_name}.out"
exit_status=0; cleanup
EOF
}

# Function to submit job to SLURM
submit_to_slurm() {
    echo; create_slurm_script
    chmod +x "${slurm_script}"
    sbatch "${slurm_script}" | sed 's/^/  /'
    rm "${slurm_script}"
    echo; exit
}

# Function to check if script is running on a compute node
check_node() {
    if [[ "$(hostname)" =~ ^n[0-9]+ ]]; then
        return 0
    else
        echo -e "\n  Error: Script not executed on a compute node. Request an interactive job first or submit to the SLURM scheduler.\n"
        exit 1
    fi
}

# Function to create and change to temporary directory
setup_temp_dir() {
    # Check if environment variable $TMPDIR is set
    if [ -z "$TMPDIR" ]; then
        echo -e "\n  Error: Environment variable \$TMPDIR not set.\n"
        exit 1
    fi

    # Create temporary directory
    temp_dir="$TMPDIR/${out_name}.$$"
    if ! mkdir -p "${temp_dir}"; then
        echo -e "\n  Error: Failed to create temporary directory.\n"
        exit 1
    fi

    temp_dir_created=1

    # Save current directory and change to temporary directory
    original_dir="$PWD"
    if ! cd "${temp_dir}"; then
        echo -e "\n  Error: Failed to change to temporary directory."
        error_flag=1
        return
    fi
}

# Function to load necessary modules
load_modules() {
    # Unload any ORCA module if loaded
    if module is-loaded chem/orca ; then
        module --quiet unload chem/orca
    fi

    # Load OpenBabel module if not already loaded
    if module list 2>&1 | grep -q 'chem/openbabel'; then
        openbabel_version=$(module list 2>&1 | grep 'chem/openbabel' | sed -n 's/.*chem\/openbabel\/\([^ ]*\).*/\1/p')
        echo -e "\n  Module OpenBabel ${openbabel_version} already loaded."
    else
        echo -e "\n  Loading default OpenBabel module..."
        module --quiet load chem/openbabel
    fi

    # Load xTB module if not already loaded
    if module list 2>&1 | grep -q 'chem/xtb'; then
        xtb_version=$(module list 2>&1 | grep 'chem/xtb' | sed -n 's/.*chem\/xtb\/\([^ ]*\).*/\1/p')
        echo "  Module xTB ${xtb_version} already loaded."
    else
        echo "  Loading default xTB module..."
        module --quiet load chem/xtb
    fi

    # Check if required commands are available
    check_command obabel
    check_command xtb

    # Set up xTB with useful machine settings
    export MKL_NUM_THREADS=4
    export OMP_NUM_THREADS=4,1
    export OMP_MAX_ACTIVE_LEVELS=1
    export OMP_STACKSIZE=2G

    # Avoid stack overflows by uncapping system stack
    ulimit -s unlimited
}

# Function to check if a command is available
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "  Error: Command $1 not available. Make sure module is loaded properly."
        error_flag=1
	return
    fi
}

# Function to generate initial guess using OpenBabel
gen_xyz() {
    { echo -e "\n                           *****************"; echo "                           * smiles2xyz.sh *"; echo "                           *****************"; } >> "${out_name}.out"

    echo -e "\nGenerating 3D molecular structure using OpenBabel..." >> "${out_name}.out"
    echo "  Generating 3D molecular structure..."

    # Run OpenBabel and handle output based on verbose flag
    if [ "$verbose" -eq 1 ]; then
        if ! obabel -:"$smiles" -oxyz -O "obabel.xyz" --gen3d --better 2>&1 | tee >(cat >> "${out_name}.out") | sed 's/^/  /'; then
            echo "Error: OpenBabel failed to generate initial guess." | tee >(cat >> "${out_name}.out") | sed 's/^/  /'
            error_flag=1
	    return
        fi
    else
        if ! obabel -:"$smiles" -oxyz -O "obabel.xyz" --gen3d --better >> "${out_name}.out" 2>&1; then
            echo "Error: OpenBabel failed to generate initial guess." | tee >(cat >> "${out_name}.out") | sed 's/^/  /'
            error_flag=1
            return
        fi
    fi

    # Check if initial guess was generated by OpenBabel
    if [ ! -s "obabel.xyz" ]; then
        echo "Error: Output file 'obabel.xyz' not created by OpenBabel." | tee >(cat >> "${out_name}.out") | sed 's/^/  /'
        error_flag=1
        return
    fi
}

# Function to optimize initial guess with xTB
xtb_opt() {
    echo -e "\nOptimizing initial guess 'obabel.xyz' using xTB..." >> "${out_name}.out"
    echo "  Optimizing initial guess using xTB..."

    # Run xTB and handle output based on verbose flag
    if [ "$verbose" -eq 1 ]; then
        if ! xtb "obabel.xyz" --chrg "$chrg" --uhf "$(( mult - 1 ))" --opt "$thresh" 2>&1 | tee >(cat >> "${out_name}.out") | sed 's/^/  /'; then
            echo "Error: xTB geometry optimization failed." | tee >(cat >> "${out_name}.out") | sed 's/^/  /'
            error_flag=1
            return
        fi
    else
        if ! xtb "obabel.xyz" --chrg "$chrg" --uhf "$(( mult - 1 ))" --opt "$thresh" >> "${out_name}.out" 2>&1; then
            echo "Error: xTB geometry optimization failed." | tee >(cat >> "${out_name}.out") | sed 's/^/  /'
            error_flag=1
            return
        fi
    fi

    # Check if output file was created by xTB
    if [ ! -s "xtbopt.xyz" ]; then
        echo "Error: Output file 'xtbopt.xyz' not created by xTB." | tee >(cat >> "${out_name}.out") | sed 's/^/  /'
        error_flag=1
        return
    fi

    # Add SMILES string to comment line and rename output
    echo -e "\nAdding SMILES string to 'xtbopt.xyz' comment line and renaming output..." >> "${out_name}.out"
    echo "  Preparing final output file..."
    awk -v smiles="$smiles" 'NR==2 {print $0 " SMILES: " smiles} NR!=2' "xtbopt.xyz" > "${out_name}.xyz"

    # Check if final output file was created successfully
    if [ ! -f "${out_name}.xyz" ]; then
        echo "Error: Final output file '${out_name}.xyz' not created." | tee >(cat >> "${out_name}.out") | sed 's/^/  /'
        error_flag=1
        return
    fi

    echo -e "\nFinal output file '${out_name}.xyz' created successfully." >> "${out_name}.out"
}

# Function to clean up temporary directory
cleanup_temp_dir() {
    if [ "${temp_dir_created}" -eq 1 ]; then
        echo -e "  Cleaning up temporary directory...\n"

        if [ "${keep_all}" -eq 1 ]; then
            # Compress temporary directory to original directory
            tar -zcf "${original_dir}/$(basename "${temp_dir}").tgz" -C "$TMPDIR" "$(basename "${temp_dir}")"
        else
            # Move final output file to original directory if it exists
            if [ -e "${out_name}.xyz" ]; then
                mv "${out_name}.xyz" "${original_dir}"
            fi

            if [ "${keep_log}" -eq 1 ] && [ -e "${out_name}.out" ]; then
                # Move logged output to original directory
                mv "${out_name}.out" "${original_dir}"
            fi
        fi
        
    	# Remove temporary directory
        rm -rf "${temp_dir}"
    fi
}

# Function to handle cleanup on exit
cleanup_on_exit() {
    cleanup_temp_dir

    if [ "${error_flag}" -eq 0 ]; then
        if [ "${temp_dir_created}" -eq 1 ]; then
            case ${exit_status} in
                0)   echo -e "  Job completed successfully. *HURRAY*\n" ;;
                130) echo -e "  Job interrupted by user (SIGINT).\n" ;;
                143) echo -e "  Job terminated by signal (SIGTERM).\n" ;;
                *)   echo -e "  Job finished with unknown exit status ${exit_status}.\n" ;;
            esac
        fi
    else
        echo -e "  Job terminated with errors. Check log for details.\n"
    fi

    # Restore terminal settings
        stty echoctl
}

# Trap interrupt and termination signals to capture exit status
trap 'exit_status=130; exit' INT
trap 'exit_status=143; exit' TERM

# Trap exit signal to perform cleanup
trap 'exit_status=${exit_status:-$?}; cleanup_on_exit; exit ${exit_status}' EXIT

# Suppress terminal output of control characters
stty -echoctl

# Main function
main() {
    if [ "$#" -eq 0 ]; then
        usage
        exit 1
    fi

    # Parse arguments
    get_args "$@"

    if [ "${submit_job}" -eq 1 ]; then
        submit_to_slurm
    else
        # Check if script is running on a compute node
        check_node

        # Create and change to temporary directory
        setup_temp_dir

        # Load necessary modules
        [ ${error_flag} -eq 0 ] && load_modules

        # Generate structure with OpenBabel and optimize with xTB
        [ ${error_flag} -eq 0 ] && gen_xyz
        [ ${error_flag} -eq 0 ] && xtb_opt
    fi
}

# Run main function
main "$@"
