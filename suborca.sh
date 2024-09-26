#!/bin/bash

# Script for submission of ORCA calculations on bwForCluster JUSTUS 2
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
show_help() {
    script_name=$(basename "$0")
    echo -e "\n\n    BASH script for submission of ORCA calculations to the SLURM scheduler on bwForCluster JUSTUS 2"
    echo -e "\n    Utilization: ${script_name} [Options] <input_file.inp>"
    echo -e "\n    Options:"
    echo "      -t walltime         Set the walltime limit in hours (default: 4 hours, maximum: 336 hours)."
    echo "      -v ORCA version     Specify the ORCA version to use for the calculation (default: 6.0.0)."
    echo "      -a add files        List additional files required for the job (default: external .xyz files"
    echo "                              specified in the ORCA input file, example: \"name.gbw ... name.hess\")."
    echo "      -s scratch space    Request node-local scratch space in GB (default: none, maximum: 7300 GB)."
    echo "      -k keep files       List files to keep after calculation (default: .out .xyz .gbw .densities"
    echo "                              .opt .hess and .interp, example: \"name_MEP_trj.xyz ... name.cis\")."
    echo -e "\n    Argument:"
    echo "      input_file.inp      The ORCA input file containing 'nprocs' and 'maxcore' values."
    echo -e "\n    Description:"
    echo "      This BASH script automates the submission of ORCA calculations to the SLURM scheduler on"
    echo "      bwForCluster JUSTUS 2. It extracts the 'nprocs' and 'maxcore' values from the ORCA input file"
    echo "      and adjusts the memory per CPU accordingly. A temporary job script with the corresponding"
    echo -e "      parameters is generated and executed, managing input/output files as well as cleanup tasks.\n\n"
}

# Check if arguments are provided
if [ "$#" -eq 0 ]; then
    show_help
    exit 1
fi

# Default parameters
walltime="04:00:00"       # Walltime in SLURM format (default: 4 hours)
max_walltime_hours="336"  # Maximum walltime for a job (336 hours)
orca_version="6.0.0"      # ORCA version (default: 6.0.0)
additional_files=()       # Array to store additional files
max_scratch_gb="7300"     # Maximum scratch space per node (7300 GB)
gres_option=""            # SLURM option --gres (default: empty)

# Parse and validate command-line arguments
while getopts ':t:v:a:s:k:h' opt; do
    case $opt in
        t)
            if ! [[ "$OPTARG" =~ ^[1-9][0-9]*$ ]]; then
                echo -e "\n  Error: Invalid value '$OPTARG' for walltime. Must be a positive integer greater than zero.\n"
                exit 1
            fi
            if [ "$OPTARG" -gt "${max_walltime_hours}" ]; then
                echo -e "\n  Error: Maximum walltime for a job is ${max_walltime_hours} hours.\n"
                exit 1
            fi
            walltime_hours=$(printf "%02d" "$OPTARG")

            # Convert walltime in hours to SLURM format hh:mm:ss
            walltime="${walltime_hours}:00:00"
            ;;
        v)
            if ! [[ "$OPTARG" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                echo -e "\n  Error: Invalid format '$OPTARG' for ORCA version. Must be in 'x.x.x' format.\n"
                exit 1
            fi
            orca_version="$OPTARG"

            # Check if specified ORCA version is available
            if ! module avail chem/orca 2>&1 | grep -qw "${orca_version}"; then
                echo -e "\n  Error: ORCA version '${orca_version}' not available. Check available versions with 'module avail chem/orca'.\n"
                exit 1
            fi
            ;;
        a)
            IFS=' ' read -r -a additional_files <<< "$OPTARG"
            
            # Check additional files and their existence
            for file in "${additional_files[@]}"; do
                if [ -n "$file" ] && [ ! -f "$file" ]; then
                    echo -e "\n  Error: Additional file '$file' does not exist.\n"
                    exit 1
                fi
            done
            ;;
        s)
            if ! [[ "$OPTARG" =~ ^[1-9][0-9]*$ ]]; then
                echo -e "\n  Error: Invalid value '$OPTARG' for scratch space. Must be a positive integer greater than zero.\n"
                exit 1
            fi
            if [ "$OPTARG" -gt "${max_scratch_gb}" ]; then
                echo -e "\n  Error: Maximum local scratch space is ${max_scratch_gb} GB per node.\n"
                exit 1
            fi
            scratch_gb="$OPTARG"

            # Define SLURM option to allocate local scratch space
            gres_option=$'#SBATCH --gres=scratch:'"${scratch_gb}"$'\n'
            ;;
        k)
            IFS=' ' read -r -a keep_files <<< "$OPTARG"
            ;;
        h)
            show_help
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

# Shift to next argument (ORCA input file)
shift $((OPTIND-1))

# Extract input filename without extension
input_file="$1"
input_name="${input_file%.*}"

# Check if ORCA input file is provided
if [ -z "${input_file}" ]; then
    echo -e "\n  Error: ORCA input file not provided.\n"
    exit 1
fi

# Check if ORCA input file exists
if [ ! -f "${input_file}" ]; then
    echo -e "\n  Error: ORCA input file '${input_file}' does not exist.\n"
    exit 1
fi

# Extract values from ORCA input file
nprocs=$(awk -v IGNORECASE=1 '
    /%pal/ { in_pal_block = 1 }
    in_pal_block && /nprocs/ {
        match($0, /nprocs[ \t]+([0-9]+)/, arr)
        if (arr[1] != "") {
            print arr[1]
            exit
        }
    }
    /^[ \t]*end/ { in_pal_block = 0 }
    ' "${input_file}")

maxcore=$(awk -v IGNORECASE=1 '
    /maxcore/ {
        match($0, /maxcore[ \t]+([0-9]+)/, arr)
        if (arr[1] != "") {
            print arr[1]
            exit
        }
    }' "${input_file}")

# Ensure extracted values are valid
if [ -z "$nprocs" ]; then
    echo -e "\n  Error: Could not extract 'nprocs' from ORCA input file.\n"
    exit 1
elif ! [[ "$nprocs" =~ ^[0-9]+$ ]] || [ "$nprocs" -lt 1 ] || [ "$nprocs" -gt 48 ]; then
    echo -e "\n  Error: Number of parallel processes must be between 1 and 48.\n"
    exit 1
fi

if [ -z "$maxcore" ]; then
    echo -e "\n  Error: Could not extract 'maxcore' from ORCA input file.\n"
    exit 1
elif ! [[ "$maxcore" =~ ^[0-9]+$ ]] || [ "$maxcore" -lt 100 ] || [ "$maxcore" -gt 29000 ]; then
    echo -e "\n  Error: Amount of scratch memory in MB must be between 100 and 29000.\n"
    exit 1
fi

# Extract .xyz files from ORCA input file
mapfile -t xyz_files < <(grep -oE '\S+\.xyz' "$1" | sed -e 's/^"//')

# Check if external .xyz files exist
for file in "${xyz_files[@]}"; do
    if [ -n "$file" ] && [ ! -f "$file" ]; then
        echo -e "\n  Error: External .xyz file '$file' does not exist.\n"
        exit 1
    fi
done

# Adjust memory per CPU
mem_per_cpu=$(awk -v maxcore="$maxcore" 'BEGIN { printf "%.0f\n", maxcore * 1.1 }')

# Determine requested amount of memory in GB
memory_gb=$(awk -v nprocs="$nprocs" -v mem_per_cpu="$mem_per_cpu" \
    'BEGIN { total = (nprocs * mem_per_cpu) / 1024; printf "%.0f\n", (total + 0.5) }')

# Print list of job specifications
echo -e "\n  Job name: ${input_name}"
echo "  Walltime limit: $walltime hours"
echo "  Process/core count per node: $nprocs"
echo "  Memory limit per core: ${mem_per_cpu} MB"
echo "  Memory limit per node: ${memory_gb} GB"
if [ -n "${scratch_gb}" ]; then
    echo "  Local scratch space: ${scratch_gb} GB"
fi

# Check if extracted values are reasonable
if [ $((48 % nprocs)) -ne 0 ]; then
    echo -e "\n  Warning: Requested number of cores is not an integer divisor of 48 (total number of cores on"
    echo "  each node). This is recommended for efficient resource utilization and maximum job throughput."
    echo "  Always consider whether your application really benefits from allocating more cores."
    read -r -p "  Continue with current settings anyway? [yes/no] " choice
    if [[ ! "$choice" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo -e "\n  Job submission canceled. Adjust number of requested cores accordingly.\n"
        exit 1
    fi
fi

# Check if requested memory exceeds threshold
if [ "${memory_gb}" -gt 187 ]; then
    echo -e "\n  Warning: Requested memory exceeds 187 GB. Slurm will rule out 456 of 692 available nodes and"
    echo "  consider only 220 nodes suitable for this job. Over-requesting memory can adversely affect the"
    echo "  wait time for this job and the priority of subsequent jobs due to resource usage accounting."
    read -r -p "  Continue with current settings anyway? [yes/no] " choice
    if [[ ! "$choice" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo -e "\n  Job submission canceled. Adjust amount of resources requested accordingly.\n"
        exit 1
    fi
fi

# Define default files to keep
keep_files+=("${input_name}.out" "${input_name}.xyz" "${input_name}.gbw" "${input_name}.densities" "${input_name}.opt" "${input_name}.hess" "${input_name}.interp")

# Create a temporary script for SLURM submission
temp_script="${input_name}.sh"

cat << EOF > "${temp_script}"
#!/bin/bash

########## BEGIN QUEUEING SYSTEM JOB PARAMETERS ################################
#
#SBATCH --job-name=${input_name}
#SBATCH --output=%x.%j.log
#SBATCH --error=%x.%j.log
#SBATCH --time=$walltime
#SBATCH --signal=B:USR1@60
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=$nprocs
#SBATCH --mem-per-cpu=${mem_per_cpu}
${gres_option}#
########## END QUEUEING SYSTEM JOB PARAMETERS ##################################

# Function to handle job timeout
timeout() {
    echo; pkill -f -o -e " ${input_file}"; sleep 10
    sed -i '/Terminated/{G}' "${input_name}.time"
    echo; cat "${input_name}.time"

    echo -e "\n\n*** JOB \${SLURM_JOB_ID} ON \$HOSTNAME CANCELED AT \`date +'%Y-%m-%d %H:%M:%S'\` DUE TO TIME LIMIT ***"

    echo -e "\n\n### Cleaning up files... removing unnecessary scratch files..."
    keep_files_pattern=\$(printf "! -name %s " ${keep_files[@]} "${input_name}_MEP.allxyz")
    echo; find \${TMP_WORK_DIR} -maxdepth 1 -type f \${keep_files_pattern} -exec rm -vf {} \;
    sleep 10 # Sleep some time so potential stale NFS handles can disappear

    echo -e "\n\n### Copying back tgz-archive of results to SLURM_SUBMIT_DIR..."
    echo; mkdir -vp "\${SLURM_SUBMIT_DIR}" # If submit directory has been deleted or moved
    echo "Creating result tgz-file '\${SLURM_SUBMIT_DIR}/\${JOB_WORK_DIR}.tgz'..."
    echo; cd "\${TMP_BASE_DIR}"
    tar -zcvf "\${SLURM_SUBMIT_DIR}/\${JOB_WORK_DIR}.tgz" "\${JOB_WORK_DIR}"

    echo -e "\n\n### Final cleanup: Removing TMP_WORK_DIR..."
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
    echo -e "\nORCA exit-code: 143"
    echo; exit 143
}

# Trap USR1 signal to handle job timeout
trap 'timeout' USR1


start=\$(date +%s)


echo -e "\n### Setting up shell environment and defaults for environment vars..."
# Reset all language and locale dependencies (write floats with a dot "."):
unset LANG; export LC_ALL="C"
# Disable all external multi-threading => MPI is in control
export MKL_NUM_THREADS=1; export OMP_NUM_THREADS=1
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

echo -e "\n### Loading software module..."
cd "\${TMP_WORK_DIR}"
module purge
module load chem/orca/${orca_version}
if [ -z "\$ORCA_VERSION" ]; then
    echo "ERROR: Failed to load 'chem/orca/${orca_version}' module."
    exit 101
fi
echo "ORCA_VERSION = \$ORCA_VERSION"
module list


echo "### Copying input files to TMP_WORK_DIR..."
echo; files_to_copy=("${input_file}" ${xyz_files[@]} ${additional_files[@]})
for file in "\${files_to_copy[@]}"; do
    if [ -n "\$file" ]; then
        cp -v "\${SLURM_SUBMIT_DIR}/\${file}" "\${TMP_WORK_DIR}"
    fi
done

scontrol show hostnames > "${input_name}.nodes"
echo -ne "\nNode list in ${input_name}.nodes: "
cat "\${TMP_WORK_DIR}/${input_name}.nodes"


echo -e "\n\n### Displaying internal ORCA environments..."
echo -e "\nORCA_BIN_DIR = \${ORCA_BIN_DIR}"
echo "ORCA_EXA_DIR = \${ORCA_EXA_DIR}"
echo "ORCA_VERSION = \${ORCA_VERSION}"


echo -e "\n\n### Starting ORCA job..."
echo -e "\nORCA starts on \$HOSTNAME in \$(pwd) with files in the working directory: \n\$(ls -1 | tr '\n' ' ')"
echo -e "\nFollowing nodes have been allocated for the job: \$SLURM_JOB_NODELIST"
echo -e "\nOMPI_MCA_mtl = \$OMPI_MCA_mtl"; echo "OMPI_MCA_pml = \$OMPI_MCA_pml"
{ time -p \$ORCA_BIN_DIR/orca "${input_name}.inp" > "${input_name}.out" 2>&1; } 2> "${input_name}.time" &

wait; orca_exit_code=\$? # Wait for background task to finish
trap - USR1 # Release signal handler for USR1
echo; cat "${input_name}.time"


echo -e "\n\n### Cleaning up files... removing unnecessary scratch files..."
keep_files_pattern=\$(printf "! -name %s " ${keep_files[@]})
echo; find \${TMP_WORK_DIR} -maxdepth 1 -type f \${keep_files_pattern} -exec rm -vf {} \;
sleep 10 # Sleep some time so potential stale NFS handles can disappear


echo -e "\n\n### Copying back tgz-archive of results to SLURM_SUBMIT_DIR..."
echo; mkdir -vp "\${SLURM_SUBMIT_DIR}" # If submit directory has been deleted or moved
echo "Creating result tgz-file '\${SLURM_SUBMIT_DIR}/\${JOB_WORK_DIR}.tgz'..."
echo; cd "\${TMP_BASE_DIR}"
tar -zcvf "\${SLURM_SUBMIT_DIR}/\${JOB_WORK_DIR}.tgz" "\${JOB_WORK_DIR}"


echo -e "\n\n### Final cleanup: Removing TMP_WORK_DIR..."
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
echo -e "\nORCA exit-code: \$orca_exit_code"
echo; exit \$orca_exit_code
EOF

# Make the temporary script executable
echo; chmod +x "${temp_script}"

# Submit the temporary script to SLURM
sbatch "${temp_script}" | sed 's/^/  /'

# Clean up the temporary script after submission
rm -f "${temp_script}"; echo
