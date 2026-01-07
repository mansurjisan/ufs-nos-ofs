#!/bin/bash
# =============================================================================
# Script Name: nos_ofs_create_datm_forcing.sh
#
# Purpose:
#   Create DATM forcing files by extracting and concatenating meteorological
#   variables from GFS/HRRR GRIB2 files for all forecast hours.
#   This creates time-series NetCDF files for use with UFS-Coastal CDEPS DATM.
#
#   The script follows the same file selection logic as the nosofs sflux
#   generation to ensure data availability in operational environments:
#   - GFS: Uses a base cycle (typically 6h before run cycle) with extended
#          forecast hours (f003-f054)
#   - HRRR: Uses hourly cycles for nowcast, then extended forecasts from
#           the run cycle (00Z/06Z/12Z/18Z) for forecast period
#
# Usage:
#   ./nos_ofs_create_datm_forcing.sh DBASE OUTPUT_DIR [TIME_START] [TIME_END]
#
# Arguments:
#   DBASE      - Data source: GFS25 or HRRR
#   OUTPUT_DIR - Directory for output files
#   TIME_START - Start time YYYYMMDDHH (optional, default: time_hotstart - 3h)
#   TIME_END   - End time YYYYMMDDHH (optional, default: time_forecastend)
#
# Environment Variables:
#   PDY        - Forecast date (YYYYMMDD)
#   cyc        - Forecast cycle (00, 06, 12, 18)
#   COMINgfs   - GFS input directory
#   COMINhrrr  - HRRR input directory
#   WGRIB2     - Path to wgrib2 executable
#   NDATE      - Path to ndate utility
#   NHOUR      - Path to nhour utility
#
# Output Files:
#   gfs_forcing.nc  - GFS forcing file (if DBASE=GFS25)
#   hrrr_forcing.nc - HRRR forcing file (if DBASE=HRRR)
#
# Author: SECOFS UFS-Coastal Transition
# Date: January 2026
# =============================================================================

set -x

# =============================================================================
# Parse Arguments
# =============================================================================
DBASE=$1
OUTPUT_DIR=$2
TIME_START=$3
TIME_END=$4

if [ -z "$DBASE" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "============================================"
    echo "Usage: $0 DBASE OUTPUT_DIR [TIME_START] [TIME_END]"
    echo ""
    echo "Arguments:"
    echo "  DBASE      - Data source: GFS25 or HRRR"
    echo "  OUTPUT_DIR - Directory for output files"
    echo "  TIME_START - Start time YYYYMMDDHH (optional)"
    echo "  TIME_END   - End time YYYYMMDDHH (optional)"
    echo ""
    echo "Environment Variables Required:"
    echo "  PDY, cyc, COMINgfs/COMINhrrr, WGRIB2, NDATE"
    echo ""
    echo "Logging Options (optional):"
    echo "  VERBOSE=0  - Quiet mode (minimal output)"
    echo "  VERBOSE=1  - Normal mode (default, shows progress)"
    echo "  VERBOSE=2  - Debug mode (shows all file selections)"
    echo "  LOG_FILE   - Path to save detailed log (optional)"
    echo ""
    echo "Example:"
    echo "  VERBOSE=2 LOG_FILE=datm.log $0 HRRR ./output"
    echo "============================================"
    exit 1
fi

# =============================================================================
# Setup Environment
# =============================================================================
WGRIB2=${WGRIB2:-wgrib2}
NDATE=${NDATE:-ndate}
NHOUR=${NHOUR:-nhour}
PDY=${PDY:-$(date +%Y%m%d)}
cyc=${cyc:-00}

# Logging options
VERBOSE=${VERBOSE:-1}           # 0=quiet, 1=normal, 2=verbose
LOG_FILE=${LOG_FILE:-""}        # Optional log file path

# Logging function
log_msg() {
    local level=$1
    shift
    local msg="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [ "$level" -le "$VERBOSE" ]; then
        echo "[$timestamp] $msg"
        if [ -n "$LOG_FILE" ]; then
            echo "[$timestamp] $msg" >> "$LOG_FILE"
        fi
    fi
}

log_info() { log_msg 1 "INFO: $@"; }
log_debug() { log_msg 2 "DEBUG: $@"; }
log_warn() { log_msg 1 "WARN: $@"; }

# Default time range if not provided
if [ -z "$TIME_START" ]; then
    # Default: PDY + cyc - 6h (nowcast start) - 3h buffer = -9h from cycle
    TIME_START=$($NDATE -9 ${PDY}${cyc})
fi
if [ -z "$TIME_END" ]; then
    # Default: PDY + cyc + 48h
    TIME_END=$($NDATE 48 ${PDY}${cyc})
fi

mkdir -p $OUTPUT_DIR
TEMP_DIR=${OUTPUT_DIR}/temp_forcing_$$
mkdir -p $TEMP_DIR

# Normalize DBASE
DBASE_UPPER=$(echo $DBASE | tr '[:lower:]' '[:upper:]')
DBASE_LOWER=$(echo $DBASE | tr '[:upper:]' '[:lower:]')
if [ "$DBASE_LOWER" == "gfs25" ]; then
    DBASE_LOWER="gfs"
fi

# Calculate total hours
TOTAL_HOURS=$($NHOUR $TIME_END $TIME_START)

echo "============================================"
echo "DATM Forcing File Generation"
echo "============================================"
echo "DBASE:       $DBASE_UPPER"
echo "TIME_START:  $TIME_START"
echo "TIME_END:    $TIME_END"
echo "TOTAL_HOURS: $TOTAL_HOURS"
echo "OUTPUT_DIR:  $OUTPUT_DIR"
echo "TEMP_DIR:    $TEMP_DIR"
echo "============================================"

# =============================================================================
# Set Data Source Parameters
# =============================================================================
if [ "$DBASE_UPPER" == "GFS" ] || [ "$DBASE_UPPER" == "GFS25" ]; then
    INTERVAL=3
    COMIN=${COMINgfs:-/lfs/h1/ops/prod/com/gfs/v16.3}
    # GFS variables to extract
    MATCH_PATTERN=":(UGRD|VGRD):10 m above ground:|:(TMP|SPFH):2 m above ground:|:PRMSL:mean sea level:|:(DSWRF|DLWRF|PRATE):surface:"
    OUTPUT_FILE=${OUTPUT_DIR}/gfs_forcing.nc

elif [ "$DBASE_UPPER" == "HRRR" ]; then
    INTERVAL=1
    COMIN=${COMINhrrr:-/lfs/h1/ops/prod/com/hrrr/v4.1}
    # HRRR uses MSLMA instead of PRMSL
    MATCH_PATTERN=":(UGRD|VGRD):10 m above ground:|:(TMP|SPFH):2 m above ground:|:MSLMA:mean sea level:|:(DSWRF|DLWRF|PRATE):surface:"
    OUTPUT_FILE=${OUTPUT_DIR}/hrrr_forcing.nc
else
    echo "ERROR: Unknown DBASE: $DBASE"
    echo "Supported values: GFS, GFS25, HRRR"
    exit 1
fi

# =============================================================================
# Function: Find GFS file for a valid time
# Strategy: Use base cycle with extended forecasts (up to f120 = 5 days)
# For operational runs, cycles from future dates won't exist, so we must
# go back far enough to find an available cycle
# =============================================================================
find_gfs_file() {
    local VALID_TIME=$1
    local VALID_DATE=$(echo $VALID_TIME | cut -c1-8)
    local VALID_HH=$(echo $VALID_TIME | cut -c9-10)

    # Calculate initial cycle (6 hours before valid time, rounded down to 00/06/12/18)
    local INIT_CYCLE_TIME=$($NDATE -6 $VALID_TIME)
    local INIT_DATE=$(echo $INIT_CYCLE_TIME | cut -c1-8)
    local INIT_HH=$(echo $INIT_CYCLE_TIME | cut -c9-10)
    local INIT_HH_NUM=$((10#$INIT_HH))

    # Round down to nearest 6-hourly cycle
    local CYCLE_HH=$(printf "%02d" $((INIT_HH_NUM / 6 * 6)))
    local CYCLE_DATE=$INIT_DATE
    local CYCLE_TIME="${CYCLE_DATE}${CYCLE_HH}"

    # Try up to 12 cycles (going back 72 hours) to handle operational scenarios
    # where future cycles don't exist yet. GFS f120 covers 5 days ahead.
    for attempt in 1 2 3 4 5 6 7 8 9 10 11 12; do
        local FHR=$($NHOUR $VALID_TIME $CYCLE_TIME 2>/dev/null || echo "-1")

        # Skip if FHR is negative or too large
        # Use 10# to force decimal interpretation (nhour can return "09" which is invalid octal)
        local FHR_DEC=$((10#$FHR))
        if [ "$FHR_DEC" -ge 0 ] && [ "$FHR_DEC" -le 120 ]; then
            local FHR_STR=$(printf "%03d" $FHR_DEC)
            local GRIB2_FILE="${COMIN}/gfs.${CYCLE_DATE}/${CYCLE_HH}/atmos/gfs.t${CYCLE_HH}z.pgrb2.0p25.f${FHR_STR}"

            if [ -s "$GRIB2_FILE" ]; then
                echo "$GRIB2_FILE"
                return 0
            fi
        fi

        # Try previous cycle (6 hours earlier)
        CYCLE_TIME=$($NDATE -6 $CYCLE_TIME)
        CYCLE_DATE=$(echo $CYCLE_TIME | cut -c1-8)
        CYCLE_HH=$(echo $CYCLE_TIME | cut -c9-10)
    done

    echo ""
    return 1
}

# =============================================================================
# Function: Find HRRR files using Fortran executable (matches SFLUX exactly)
# Uses nos_ofs_met_file_search for operational consistency
# =============================================================================

# Track files used for logging
declare -a FILES_USED=()
HRRR_FILE_LIST=""

# Fortran executable path
MET_FILE_SEARCH=${EXECnos:-/lfs/h1/ops/prod/packages/nosofs.v3.7.0/exec}/nos_ofs_met_file_search

find_hrrr_files_fortran() {
    log_info "Using Fortran file search (nos_ofs_met_file_search) for HRRR..."
    log_info "  TIME_START: $TIME_START"
    log_info "  TIME_END: $TIME_END"

    # Create working directory for file search
    local SEARCH_DIR="${TEMP_DIR}/file_search"
    mkdir -p $SEARCH_DIR
    cd $SEARCH_DIR

    # Step 1: Collect all available HRRR files into tmp.out (same as SFLUX)
    log_info "  Collecting available HRRR files..."
    rm -f tmp.out

    # Get date range to search
    local START_DATE=$(echo $TIME_START | cut -c1-8)
    local END_DATE=$(echo $TIME_END | cut -c1-8)
    local CURRENTTIME=$TIME_START

    # Search from 2 days before start to end date
    local SEARCH_START=$($NDATE -48 $TIME_START)
    local SEARCH_DATE=$(echo $SEARCH_START | cut -c1-8)

    while [ "$SEARCH_DATE" -le "$END_DATE" ]; do
        # Check each hourly cycle (00-23)
        for cycle_hr in $(seq -w 0 23); do
            local CYCLE_STR=$(printf "%02d" $((10#$cycle_hr)))

            # Check if cycle has f48 available (required for forecast coverage)
            local TEST_F48="${COMIN}/hrrr.${SEARCH_DATE}/conus/hrrr.t${CYCLE_STR}z.wrfsfcf48.grib2"
            if [ -s "$TEST_F48" ] || [ -s "${TEST_F48}.idx" ]; then
                # Add all forecast hours (f01-f48) for this cycle
                for fhr in $(seq -w 1 48); do
                    local HRRR_FILE="${COMIN}/hrrr.${SEARCH_DATE}/conus/hrrr.t${CYCLE_STR}z.wrfsfcf${fhr}.grib2"
                    if [ -s "$HRRR_FILE" ] || [ -s "${HRRR_FILE}.idx" ]; then
                        echo "$HRRR_FILE" >> tmp.out
                    fi
                done
                log_debug "  Found cycle: ${SEARCH_DATE} ${CYCLE_STR}z with f48"
            fi
        done

        # Next day
        SEARCH_DATE=$($NDATE 24 ${SEARCH_DATE}00 | cut -c1-8)
    done

    if [ ! -s tmp.out ]; then
        log_warn "No HRRR files found!"
        return 1
    fi

    local NFILES=$(wc -l < tmp.out)
    log_info "  Found $NFILES HRRR files"

    # Step 2: Create control file for Fortran executable
    # Format: TIME_START, nowcastend, TIME_END, input_file, output_file
    local NOWCASTEND=${time_nowcastend:-$TIME_START}
    local MET_FILE="HRRR_FILE_DATM.dat"

    cat > Fortran_file_search.ctl << EOF
$TIME_START
$NOWCASTEND
$TIME_END
tmp.out
$MET_FILE
EOF

    log_debug "  Control file:"
    log_debug "    TIME_START: $TIME_START"
    log_debug "    NOWCASTEND: $NOWCASTEND"
    log_debug "    TIME_END: $TIME_END"

    # Step 3: Run Fortran file search executable
    if [ ! -x "$MET_FILE_SEARCH" ]; then
        log_warn "Fortran executable not found: $MET_FILE_SEARCH"
        log_warn "Falling back to bash file selection"
        cd - > /dev/null
        return 1
    fi

    log_info "  Running nos_ofs_met_file_search..."
    $MET_FILE_SEARCH < Fortran_file_search.ctl > Fortran_file_search.log 2>&1
    local RC=$?

    if grep -q "COMPLETED SUCCESSFULLY" Fortran_file_search.log; then
        log_info "  File search COMPLETED SUCCESSFULLY"
    else
        log_warn "  File search may have issues - check Fortran_file_search.log"
    fi

    # Step 4: Read selected files
    if [ -s "$MET_FILE" ]; then
        HRRR_FILE_LIST="$SEARCH_DIR/$MET_FILE"
        local NSELECTED=$(grep -c "^/" "$MET_FILE" 2>/dev/null || echo "0")
        log_info "  Selected $NSELECTED files for processing"

        # Copy file search artifacts to output directory for debugging
        cp -p tmp.out ${OUTPUT_DIR}/hrrr_files_available.txt 2>/dev/null
        cp -p Fortran_file_search.ctl ${OUTPUT_DIR}/hrrr_file_search.ctl 2>/dev/null
        cp -p Fortran_file_search.log ${OUTPUT_DIR}/hrrr_file_search.log 2>/dev/null
        cp -p $MET_FILE ${OUTPUT_DIR}/hrrr_files_selected.dat 2>/dev/null
        log_info "  File search logs copied to ${OUTPUT_DIR}/"

        # Log the selected files
        if [ "$VERBOSE" -ge 2 ]; then
            log_debug "  Selected files:"
            while IFS= read -r line; do
                if [[ "$line" == /* ]]; then
                    log_debug "    $line"
                fi
            done < "$MET_FILE"
        fi
    else
        log_warn "  No output file generated"
        cd - > /dev/null
        return 1
    fi

    cd - > /dev/null
    return 0
}

# =============================================================================
# Function: Get HRRR file for a valid time from Fortran-selected list
# =============================================================================
get_hrrr_file_from_list() {
    local VALID_TIME=$1

    if [ -z "$HRRR_FILE_LIST" ] || [ ! -s "$HRRR_FILE_LIST" ]; then
        echo ""
        return 1
    fi

    # Parse the Fortran output file
    # Format: filepath followed by date line (YYYY MM DD CYC FHR)
    local VALID_DATE=$(echo $VALID_TIME | cut -c1-8)
    local VALID_HH=$(echo $VALID_TIME | cut -c9-10)

    local FOUND_FILE=""
    local PREV_LINE=""

    while IFS= read -r line; do
        if [[ "$line" == /* ]]; then
            PREV_LINE="$line"
        else
            # Parse date line: YYYY MM DD CYC FHR
            local FILE_YEAR=$(echo $line | awk '{print $1}')
            local FILE_MON=$(echo $line | awk '{print $2}')
            local FILE_DAY=$(echo $line | awk '{print $3}')
            local FILE_CYC=$(echo $line | awk '{print $4}')
            local FILE_FHR=$(echo $line | awk '{print $5}')

            # Calculate valid time for this file
            local FILE_DATE="${FILE_YEAR}$(printf '%02d' $FILE_MON)$(printf '%02d' $FILE_DAY)"
            local FILE_VALID_HH=$((10#$FILE_CYC + 10#$FILE_FHR))

            # Handle day rollover
            while [ $FILE_VALID_HH -ge 24 ]; do
                FILE_VALID_HH=$((FILE_VALID_HH - 24))
                FILE_DATE=$($NDATE 24 ${FILE_DATE}00 | cut -c1-8)
            done

            local FILE_VALID_TIME="${FILE_DATE}$(printf '%02d' $FILE_VALID_HH)"

            if [ "$FILE_VALID_TIME" == "$VALID_TIME" ]; then
                FOUND_FILE="$PREV_LINE"
                FILES_USED+=("$VALID_TIME|${FILE_CYC}z|f$(printf '%02d' $FILE_FHR)|$(basename $PREV_LINE)")
                break
            fi
        fi
    done < "$HRRR_FILE_LIST"

    echo "$FOUND_FILE"
}

# =============================================================================
# Function: Find HRRR file (wrapper - tries Fortran first, then bash fallback)
# =============================================================================
HRRR_FORTRAN_INITIALIZED=0

find_hrrr_file() {
    local VALID_TIME=$1

    # Initialize Fortran file list on first call
    if [ "$HRRR_FORTRAN_INITIALIZED" -eq 0 ]; then
        find_hrrr_files_fortran
        HRRR_FORTRAN_INITIALIZED=1
    fi

    # Try to get file from Fortran-selected list
    local GRIB2_FILE=$(get_hrrr_file_from_list $VALID_TIME)

    if [ -n "$GRIB2_FILE" ] && [ -s "$GRIB2_FILE" ]; then
        log_debug "$VALID_TIME -> $(basename $GRIB2_FILE)"
        echo "$GRIB2_FILE"
        return 0
    fi

    log_warn "$VALID_TIME -> No HRRR file found in Fortran selection"
    echo ""
    return 1
}

# =============================================================================
# Function: Print summary of files used
# =============================================================================
print_files_summary() {
    log_info ""
    log_info "============================================"
    log_info "SUMMARY: GRIB2 FILES USED (Fortran selection)"
    log_info "============================================"
    log_info ""
    log_info "Valid Time       | Cycle | FHR  | File"
    log_info "-----------------|-------|------|----------------------------------"

    for entry in "${FILES_USED[@]}"; do
        local vtime=$(echo $entry | cut -d'|' -f1)
        local cycle=$(echo $entry | cut -d'|' -f2)
        local fhr=$(echo $entry | cut -d'|' -f3)
        local fname=$(echo $entry | cut -d'|' -f4)
        log_info "$vtime | $cycle  | $fhr  | $fname"
    done
    log_info "============================================"
    log_info "Total files: ${#FILES_USED[@]}"
    log_info ""
}

# =============================================================================
# Step 1: Find and extract variables for each timestep
# =============================================================================
echo ""
echo "Step 1: Finding GRIB2 files for time range..."
echo "============================================"

FILE_COUNT=0
MISSING_COUNT=0
CURRENT_TIME=$TIME_START
FILE_LIST=""

while [ "$CURRENT_TIME" -le "$TIME_END" ]; do
    TIME_STR=$CURRENT_TIME
    NC_FILE="${TEMP_DIR}/${DBASE_LOWER}_${TIME_STR}.nc"

    # Find the appropriate GRIB2 file
    if [ "$DBASE_UPPER" == "GFS" ] || [ "$DBASE_UPPER" == "GFS25" ]; then
        GRIB2_FILE=$(find_gfs_file $CURRENT_TIME)
    else
        GRIB2_FILE=$(find_hrrr_file $CURRENT_TIME)
    fi

    if [ -n "$GRIB2_FILE" ] && [ -s "$GRIB2_FILE" ]; then
        echo "Processing ${TIME_STR}: $GRIB2_FILE"

        $WGRIB2 $GRIB2_FILE \
            -match "$MATCH_PATTERN" \
            -netcdf $NC_FILE

        if [ -s "$NC_FILE" ]; then
            FILE_COUNT=$((FILE_COUNT + 1))
            FILE_LIST="$FILE_LIST $NC_FILE"
        else
            echo "WARNING: Failed to extract data for $TIME_STR"
            MISSING_COUNT=$((MISSING_COUNT + 1))
        fi
    else
        echo "WARNING: No file found for valid time $TIME_STR"
        MISSING_COUNT=$((MISSING_COUNT + 1))
    fi

    # Advance to next timestep
    CURRENT_TIME=$($NDATE $INTERVAL $CURRENT_TIME)
done

echo ""
echo "Extracted $FILE_COUNT files, $MISSING_COUNT missing"

if [ $FILE_COUNT -eq 0 ]; then
    echo "ERROR: No files extracted. Check input paths."
    rm -rf $TEMP_DIR
    exit 1
fi

# =============================================================================
# Step 2: Concatenate files along time dimension
# =============================================================================
echo ""
echo "Step 2: Concatenating files..."
echo "============================================"

# Sort files by name (which sorts by time due to naming convention)
NC_FILES=$(ls -1 ${TEMP_DIR}/${DBASE_LOWER}_*.nc 2>/dev/null | sort)
NUM_FILES=$(echo "$NC_FILES" | wc -l)
echo "Found $NUM_FILES NetCDF files to concatenate"

if [ -z "$NC_FILES" ]; then
    echo "ERROR: No NetCDF files found to concatenate"
    rm -rf $TEMP_DIR
    exit 1
fi

# Use NCO ncrcat for concatenation
if command -v ncrcat &> /dev/null; then
    echo "Using NCO ncrcat for concatenation..."
    ncrcat -O $NC_FILES ${OUTPUT_DIR}/${DBASE_LOWER}_forcing_raw.nc
    CONCAT_STATUS=$?
else
    echo "ERROR: ncrcat not found. Please load NCO module."
    rm -rf $TEMP_DIR
    exit 1
fi

if [ $CONCAT_STATUS -ne 0 ] || [ ! -s ${OUTPUT_DIR}/${DBASE_LOWER}_forcing_raw.nc ]; then
    echo "ERROR: Concatenation failed"
    rm -rf $TEMP_DIR
    exit 1
fi

echo "Created: ${OUTPUT_DIR}/${DBASE_LOWER}_forcing_raw.nc"

# =============================================================================
# Step 3: Add CF-compliance and CDEPS-compatible time attributes
# =============================================================================
echo ""
echo "Step 3: Adding CF-compliance and CDEPS time attributes..."
echo "============================================"

cp ${OUTPUT_DIR}/${DBASE_LOWER}_forcing_raw.nc $OUTPUT_FILE

# Add global attributes
if command -v ncatted &> /dev/null; then
    ncatted -h -a Conventions,global,o,c,"CF-1.6" $OUTPUT_FILE
    ncatted -h -a title,global,o,c,"${DBASE_UPPER} forcing data for UFS-Coastal DATM" $OUTPUT_FILE
    ncatted -h -a source,global,o,c,"NCEP ${DBASE_UPPER}" $OUTPUT_FILE
    ncatted -h -a institution,global,o,c,"NOAA/NOS/OCS" $OUTPUT_FILE
    ncatted -h -a history,global,o,c,"Created by nos_ofs_create_datm_forcing.sh on $(date)" $OUTPUT_FILE

    # Add coordinate attributes
    ncatted -h -a units,longitude,o,c,"degrees_east" $OUTPUT_FILE
    ncatted -h -a axis,longitude,o,c,"X" $OUTPUT_FILE
    ncatted -h -a standard_name,longitude,o,c,"longitude" $OUTPUT_FILE

    ncatted -h -a units,latitude,o,c,"degrees_north" $OUTPUT_FILE
    ncatted -h -a axis,latitude,o,c,"Y" $OUTPUT_FILE
    ncatted -h -a standard_name,latitude,o,c,"latitude" $OUTPUT_FILE

    ncatted -h -a axis,time,o,c,"T" $OUTPUT_FILE

    # =========================================================================
    # CRITICAL: CDEPS/ESMF-compatible time attributes
    # Without these, shr_stream_findBounds will fail with:
    #   "ERROR: limit on and rDateIn lt rDatelvd"
    # CDEPS requires epoch-based time units and calendar attribute for proper
    # date parsing by the ESMF time manager.
    # =========================================================================
    echo "Adding CDEPS-compatible time attributes..."

    # Set time units to epoch format (required by CDEPS)
    ncatted -O -a units,time,o,c,"seconds since 1970-01-01 00:00:00" $OUTPUT_FILE

    # Add calendar attribute (required by CDEPS/ESMF time manager)
    ncatted -O -a calendar,time,o,c,"standard" $OUTPUT_FILE

    # Remove potentially conflicting reference time attributes that confuse CDEPS
    # These are sometimes added by wgrib2 and can cause date misinterpretation
    ncatted -O -a reference_time,time,d,, $OUTPUT_FILE 2>/dev/null || true
    ncatted -O -a reference_date,time,d,, $OUTPUT_FILE 2>/dev/null || true
    ncatted -O -a reference_time_type,time,d,, $OUTPUT_FILE 2>/dev/null || true
    ncatted -O -a reference_time_description,time,d,, $OUTPUT_FILE 2>/dev/null || true

    echo "CDEPS time attributes added successfully"
fi

echo "Created: $OUTPUT_FILE"

# =============================================================================
# Step 4: Verify output
# =============================================================================
echo ""
echo "Step 4: Verifying output..."
echo "============================================"

if command -v ncdump &> /dev/null; then
    TIME_STEPS=$(ncdump -h $OUTPUT_FILE | grep "time = " | head -1 | sed 's/.*time = \([0-9]*\).*/\1/')
fi
FILE_SIZE=$(ls -lh $OUTPUT_FILE | awk '{print $5}')

echo "Output file: $OUTPUT_FILE"
echo "File size:   $FILE_SIZE"
echo "Time steps:  $TIME_STEPS"
echo ""

if command -v ncdump &> /dev/null; then
    echo "Variables:"
    ncdump -h $OUTPUT_FILE | grep -E "^\s+(float|double)" | head -10
fi

# =============================================================================
# Cleanup
# =============================================================================
echo ""
echo "Cleaning up temporary files..."
rm -rf $TEMP_DIR
rm -f ${OUTPUT_DIR}/${DBASE_LOWER}_forcing_raw.nc

# Print summary of files used (if HRRR and verbose mode)
if [ "$DBASE_UPPER" == "HRRR" ] && [ "$VERBOSE" -ge 1 ]; then
    print_files_summary
fi

echo ""
echo "============================================"
echo "DATM Forcing Generation COMPLETED"
echo "============================================"
echo "Output: $OUTPUT_FILE"
echo "Time range: $TIME_START to $TIME_END"
echo "Time steps: $TIME_STEPS"
if [ "$DBASE_UPPER" == "HRRR" ]; then
    echo "File selection: nos_ofs_met_file_search (Fortran)"
fi
echo "============================================"

# Save file list to log if LOG_FILE specified
if [ -n "$LOG_FILE" ] && [ "$DBASE_UPPER" == "HRRR" ]; then
    echo "" >> "$LOG_FILE"
    echo "FILES_USED:" >> "$LOG_FILE"
    for entry in "${FILES_USED[@]}"; do
        echo "  $entry" >> "$LOG_FILE"
    done
fi

exit 0
