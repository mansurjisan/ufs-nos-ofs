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
# Function: Find HRRR base cycle (matches SFLUX logic)
# Strategy: Find the latest hourly cycle that has f48 available
#           Use this SINGLE cycle for ALL valid times with extended forecasts
# This ensures DATM and SFLUX use identical HRRR data sources
# =============================================================================
HRRR_BASE_CYCLE=""
HRRR_BASE_DATE=""

find_hrrr_base_cycle() {
    # Only find once - cache result
    if [ -n "$HRRR_BASE_CYCLE" ] && [ -n "$HRRR_BASE_DATE" ]; then
        return 0
    fi

    echo "  Finding HRRR base cycle with f48 available..."

    # Start from TIME_START and search backward for cycles with f48
    local SEARCH_TIME=$TIME_START
    local SEARCH_DATE=$(echo $SEARCH_TIME | cut -c1-8)

    # Search up to 48 hours back
    for back_days in 0 1 2; do
        local CHECK_DATE=$($NDATE -$((back_days * 24)) ${SEARCH_DATE}00 | cut -c1-8)

        # Check each hourly cycle (23 down to 00)
        for cycle_hr in 23 22 21 20 19 18 17 16 15 14 13 12 11 10 09 08 07 06 05 04 03 02 01 00; do
            local CYCLE_STR=$(printf "%02d" $((10#$cycle_hr)))
            local TEST_FILE="${COMIN}/hrrr.${CHECK_DATE}/conus/hrrr.t${CYCLE_STR}z.wrfsfcf48.grib2"

            if [ -s "$TEST_FILE" ] || [ -s "${TEST_FILE}.idx" ]; then
                HRRR_BASE_DATE=$CHECK_DATE
                HRRR_BASE_CYCLE=$CYCLE_STR
                echo "  Found HRRR base cycle: ${HRRR_BASE_DATE} ${HRRR_BASE_CYCLE}z (has f48)"
                return 0
            fi
        done
    done

    echo "WARNING: No HRRR cycle with f48 found, falling back to latest available"
    return 1
}

# =============================================================================
# Function: Find HRRR file for a valid time (SFLUX-matching logic)
# Uses single base cycle with extended forecast hours (f01-f48)
# =============================================================================
find_hrrr_file() {
    local VALID_TIME=$1

    # Ensure we have the base cycle
    find_hrrr_base_cycle

    if [ -z "$HRRR_BASE_CYCLE" ] || [ -z "$HRRR_BASE_DATE" ]; then
        echo ""
        return 1
    fi

    # Calculate forecast hour from base cycle to valid time
    local BASE_TIME="${HRRR_BASE_DATE}${HRRR_BASE_CYCLE}"
    local FHR=$($NHOUR $VALID_TIME $BASE_TIME 2>/dev/null || echo "-1")

    # Handle decimal interpretation
    local FHR_DEC=$((10#$FHR))

    if [ "$FHR_DEC" -ge 1 ] && [ "$FHR_DEC" -le 48 ]; then
        local FHR_STR=$(printf "%02d" $FHR_DEC)
        local GRIB2_FILE="${COMIN}/hrrr.${HRRR_BASE_DATE}/conus/hrrr.t${HRRR_BASE_CYCLE}z.wrfsfcf${FHR_STR}.grib2"

        if [ -s "$GRIB2_FILE" ]; then
            echo "$GRIB2_FILE"
            return 0
        fi
    fi

    # Fallback: try hourly cycle with f01 if forecast hour out of range
    if [ "$FHR_DEC" -lt 1 ] || [ "$FHR_DEC" -gt 48 ]; then
        local PREV_HOUR_TIME=$($NDATE -1 $VALID_TIME)
        local PREV_DATE=$(echo $PREV_HOUR_TIME | cut -c1-8)
        local PREV_HH=$(echo $PREV_HOUR_TIME | cut -c9-10)

        local GRIB2_FILE="${COMIN}/hrrr.${PREV_DATE}/conus/hrrr.t${PREV_HH}z.wrfsfcf01.grib2"
        if [ -s "$GRIB2_FILE" ]; then
            echo "$GRIB2_FILE"
            return 0
        fi
    fi

    echo ""
    return 1
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

echo ""
echo "============================================"
echo "DATM Forcing Generation COMPLETED"
echo "============================================"
echo "Output: $OUTPUT_FILE"
echo "Time range: $TIME_START to $TIME_END"
echo "Time steps: $TIME_STEPS"
echo "============================================"

exit 0
