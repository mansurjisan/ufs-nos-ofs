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
# Strategy: Use base cycle (typically 18Z for 00Z run) with extended forecasts
# =============================================================================
find_gfs_file() {
    local VALID_TIME=$1
    local VALID_DATE=$(echo $VALID_TIME | cut -c1-8)
    local VALID_HH=$(echo $VALID_TIME | cut -c9-10)

    # Try cycles in order of preference: 18Z, 12Z, 06Z, 00Z from previous days
    # Start with the cycle 6 hours before valid time, then go backwards
    local VALID_EPOCH=$($NDATE 0 $VALID_TIME | cut -c1-10)

    # Calculate initial cycle (6 hours before valid time, rounded down to 00/06/12/18)
    local INIT_CYCLE_TIME=$($NDATE -6 $VALID_TIME)
    local INIT_DATE=$(echo $INIT_CYCLE_TIME | cut -c1-8)
    local INIT_HH=$(echo $INIT_CYCLE_TIME | cut -c9-10)
    local INIT_HH_NUM=$((10#$INIT_HH))

    # Round down to nearest 6-hourly cycle
    local CYCLE_HH=$(printf "%02d" $((INIT_HH_NUM / 6 * 6)))
    local CYCLE_DATE=$INIT_DATE
    local CYCLE_TIME="${CYCLE_DATE}${CYCLE_HH}"

    # Try up to 4 cycles (going back 24 hours)
    for attempt in 1 2 3 4; do
        local FHR=$($NHOUR $VALID_TIME $CYCLE_TIME 2>/dev/null || echo "-1")

        # Skip if FHR is negative or too large
        if [ "$FHR" -ge 0 ] && [ "$FHR" -le 120 ]; then
            local FHR_STR=$(printf "%03d" $FHR)
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
# Function: Find HRRR file for a valid time
# Strategy:
#   - For past hours: Use hourly cycles with f01 (previous hour's cycle)
#   - For future hours: Use 00Z/06Z/12Z/18Z cycle with extended forecasts
# =============================================================================
find_hrrr_file() {
    local VALID_TIME=$1
    local VALID_DATE=$(echo $VALID_TIME | cut -c1-8)
    local VALID_HH=$(echo $VALID_TIME | cut -c9-10)
    local VALID_HH_NUM=$((10#$VALID_HH))

    # Current run cycle time
    local RUN_CYCLE_TIME="${PDY}${cyc}"

    # Check if this valid time is before or after the run cycle
    local HOURS_FROM_CYCLE=$($NHOUR $VALID_TIME $RUN_CYCLE_TIME 2>/dev/null || echo "0")

    # Strategy 1: For times before or at run cycle, use hourly cycles with f01
    # (This matches Machuan's approach for nowcast period)
    if [ "$HOURS_FROM_CYCLE" -le 0 ]; then
        # Use previous hour's cycle with f01
        local PREV_HOUR_TIME=$($NDATE -1 $VALID_TIME)
        local PREV_DATE=$(echo $PREV_HOUR_TIME | cut -c1-8)
        local PREV_HH=$(echo $PREV_HOUR_TIME | cut -c9-10)

        local GRIB2_FILE="${COMIN}/hrrr.${PREV_DATE}/conus/hrrr.t${PREV_HH}z.wrfsfcf01.grib2"
        if [ -s "$GRIB2_FILE" ]; then
            echo "$GRIB2_FILE"
            return 0
        fi
    fi

    # Strategy 2: For times after run cycle, use run cycle with extended forecasts
    # (This matches Machuan's approach for forecast period)
    if [ "$HOURS_FROM_CYCLE" -gt 0 ]; then
        local FHR=$HOURS_FROM_CYCLE
        if [ "$FHR" -ge 1 ] && [ "$FHR" -le 48 ]; then
            local FHR_STR=$(printf "%02d" $FHR)
            local GRIB2_FILE="${COMIN}/hrrr.${PDY}/conus/hrrr.t${cyc}z.wrfsfcf${FHR_STR}.grib2"
            if [ -s "$GRIB2_FILE" ]; then
                echo "$GRIB2_FILE"
                return 0
            fi
        fi
    fi

    # Strategy 3: Fallback - try previous hourly cycles with f01
    for back_hours in 1 2 3 4; do
        local TRY_TIME=$($NDATE -$back_hours $VALID_TIME)
        local TRY_DATE=$(echo $TRY_TIME | cut -c1-8)
        local TRY_HH=$(echo $TRY_TIME | cut -c9-10)
        local FHR=$back_hours
        local FHR_STR=$(printf "%02d" $FHR)

        local GRIB2_FILE="${COMIN}/hrrr.${TRY_DATE}/conus/hrrr.t${TRY_HH}z.wrfsfcf${FHR_STR}.grib2"
        if [ -s "$GRIB2_FILE" ]; then
            echo "$GRIB2_FILE"
            return 0
        fi
    done

    # Strategy 4: Fallback - try 6-hourly cycles (00Z, 06Z, 12Z, 18Z) with extended forecasts
    local INIT_TIME=$($NDATE -6 $VALID_TIME)
    local INIT_DATE=$(echo $INIT_TIME | cut -c1-8)
    local INIT_HH_NUM=$((10#$(echo $INIT_TIME | cut -c9-10)))
    local CYCLE_HH=$(printf "%02d" $((INIT_HH_NUM / 6 * 6)))
    local CYCLE_TIME="${INIT_DATE}${CYCLE_HH}"

    for attempt in 1 2 3 4; do
        local FHR=$($NHOUR $VALID_TIME $CYCLE_TIME 2>/dev/null || echo "-1")
        local CYCLE_DATE=$(echo $CYCLE_TIME | cut -c1-8)
        local CYCLE_HH_STR=$(echo $CYCLE_TIME | cut -c9-10)

        if [ "$FHR" -ge 1 ] && [ "$FHR" -le 48 ]; then
            local FHR_STR=$(printf "%02d" $FHR)
            local GRIB2_FILE="${COMIN}/hrrr.${CYCLE_DATE}/conus/hrrr.t${CYCLE_HH_STR}z.wrfsfcf${FHR_STR}.grib2"
            if [ -s "$GRIB2_FILE" ]; then
                echo "$GRIB2_FILE"
                return 0
            fi
        fi

        # Try previous 6-hourly cycle
        CYCLE_TIME=$($NDATE -6 $CYCLE_TIME)
    done

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
# Step 3: Add CF-compliance attributes
# =============================================================================
echo ""
echo "Step 3: Adding CF-compliance attributes..."
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
