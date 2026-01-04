#!/bin/bash
#############################################
# nos_ofs_gen_ufs_config.sh
#
# Generate UFS-Coastal configuration files from templates
# for SECOFS and other SCHISM-based OFS systems
#
# Usage:
#   nos_ofs_gen_ufs_config.sh [OPTIONS]
#
# Required Environment Variables:
#   PDY        - Forecast date (YYYYMMDD)
#   cyc        - Cycle hour (00, 06, 12, 18)
#   DATA       - Working directory
#   FIXofs     - Fix files directory (contains templates)
#
# Optional Environment Variables:
#   NHOURS     - Forecast length (default: 48)
#   DT_ATMOS   - Atmospheric timestep (default: 120)
#   NX_GFS     - GFS grid x-dimension (default: 101)
#   NY_GFS     - GFS grid y-dimension (default: 93)
#   USE_HRRR   - Include HRRR stream (default: true)
#
# Output Files (in $DATA):
#   model_configure
#   datm_in
#   datm.streams
#   ufs.configure (copied from FIXofs)
#
# Author: Generated for SECOFS UFS-Coastal transition
# Date: January 2026
#############################################

set -eu

#############################################
# Parse Arguments
#############################################
VERBOSE=${VERBOSE:-false}

while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [-v|--verbose] [-h|--help]"
            echo ""
            echo "Generate UFS-Coastal config files from templates"
            echo ""
            echo "Required environment variables:"
            echo "  PDY, cyc, DATA, FIXofs"
            echo ""
            echo "Optional environment variables:"
            echo "  NHOURS, DT_ATMOS, NX_GFS, NY_GFS, USE_HRRR"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

#############################################
# Validate Required Variables
#############################################
log_msg() {
    if [ "$VERBOSE" == "true" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    fi
}

error_exit() {
    echo "ERROR: $1" >&2
    exit 1
}

[ -z "${PDY:-}" ] && error_exit "PDY not set"
[ -z "${cyc:-}" ] && error_exit "cyc not set"
[ -z "${DATA:-}" ] && error_exit "DATA not set"
[ -z "${FIXofs:-}" ] && error_exit "FIXofs not set"

#############################################
# Set Default Values
#############################################
NHOURS=${NHOURS:-48}
DT_ATMOS=${DT_ATMOS:-120}
NX_GFS=${NX_GFS:-101}
NY_GFS=${NY_GFS:-93}
USE_HRRR=${USE_HRRR:-true}

# Extract date components
YYYY=${PDY:0:4}
MM=${PDY:4:2}
DD=${PDY:6:2}
HH=${cyc}

log_msg "============================================"
log_msg "UFS-Coastal Config Generation"
log_msg "============================================"
log_msg "PDY:      $PDY"
log_msg "cyc:      $cyc"
log_msg "DATA:     $DATA"
log_msg "FIXofs:   $FIXofs"
log_msg "NHOURS:   $NHOURS"
log_msg "DT_ATMOS: $DT_ATMOS"
log_msg "USE_HRRR: $USE_HRRR"
log_msg "============================================"

#############################################
# Check Template Files Exist
#############################################
TEMPLATE_DIR="${FIXofs}"

for template in model_configure.template datm_in.template datm.streams.template ufs.configure; do
    if [ ! -f "${TEMPLATE_DIR}/${template}" ]; then
        error_exit "Template not found: ${TEMPLATE_DIR}/${template}"
    fi
done

log_msg "All template files found"

#############################################
# Create INPUT directory if needed
#############################################
mkdir -p ${DATA}/INPUT

#############################################
# Generate model_configure
#############################################
log_msg "Generating model_configure..."

sed -e "s/@\[YYYY\]/${YYYY}/g" \
    -e "s/@\[MM\]/${MM}/g" \
    -e "s/@\[DD\]/${DD}/g" \
    -e "s/@\[HH\]/${HH}/g" \
    -e "s/@\[NHOURS\]/${NHOURS}/g" \
    -e "s/@\[DT_ATMOS\]/${DT_ATMOS}/g" \
    ${TEMPLATE_DIR}/model_configure.template > ${DATA}/model_configure

log_msg "Created: ${DATA}/model_configure"

#############################################
# Generate datm_in
#############################################
log_msg "Generating datm_in..."

sed -e "s|@\[DATA\]|${DATA}|g" \
    -e "s/@\[NX_GFS\]/${NX_GFS}/g" \
    -e "s/@\[NY_GFS\]/${NY_GFS}/g" \
    ${TEMPLATE_DIR}/datm_in.template > ${DATA}/datm_in

log_msg "Created: ${DATA}/datm_in"

#############################################
# Generate datm.streams
#############################################
log_msg "Generating datm.streams..."

sed -e "s/@\[YYYY\]/${YYYY}/g" \
    -e "s|@\[DATA\]|${DATA}|g" \
    ${TEMPLATE_DIR}/datm.streams.template > ${DATA}/datm.streams

# Optionally remove HRRR stream if not using
if [ "$USE_HRRR" != "true" ]; then
    log_msg "Removing HRRR stream from datm.streams..."
    # Comment out HRRR section (stream 02)
    sed -i '/^!# Stream 02: HRRR/,/^!#$/{ s/^/!/ }' ${DATA}/datm.streams
    sed -i '/^stream_info:.*hrrr/,/stream_data_variables02:/{ s/^/!/ }' ${DATA}/datm.streams
fi

log_msg "Created: ${DATA}/datm.streams"

#############################################
# Copy ufs.configure (static)
#############################################
log_msg "Copying ufs.configure..."

cp ${TEMPLATE_DIR}/ufs.configure ${DATA}/ufs.configure

log_msg "Created: ${DATA}/ufs.configure"

#############################################
# Verify Output Files
#############################################
log_msg "============================================"
log_msg "Verifying output files..."

for config in model_configure datm_in datm.streams ufs.configure; do
    if [ -f "${DATA}/${config}" ]; then
        log_msg "OK: ${config} ($(wc -l < ${DATA}/${config}) lines)"
    else
        error_exit "Failed to create: ${config}"
    fi
done

log_msg "============================================"
log_msg "UFS-Coastal config generation complete!"
log_msg "============================================"

exit 0
