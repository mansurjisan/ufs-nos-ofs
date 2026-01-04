#!/bin/bash
# =============================================================================
# Script Name: nos_ofs_create_datm_forcing.sh
#
# Purpose:
#   Create DATM forcing files by extracting and concatenating meteorological
#   variables from GFS/HRRR GRIB2 files for nowcast+forecast periods.
#   This creates time-series NetCDF files for use with UFS-Coastal CDEPS DATM.
#
# Usage:
#   ./nos_ofs_create_datm_forcing.sh DBASE OUTPUT_DIR [TIME_START TIME_END]
#
# Arguments:
#   DBASE      - Data source: GFS25 or HRRR
#   OUTPUT_DIR - Directory for output files
#   TIME_START - Start time (YYYYMMDDHH) - optional, defaults to time_hotstart
#   TIME_END   - End time (YYYYMMDDHH) - optional, defaults to time_forecastend
#
# Environment Variables:
#   time_hotstart    - Nowcast start time (from restart file)
#   time_nowcastend  - Current cycle time (PDY+cyc)
#   time_forecastend - Forecast end time
#   COMINgfs         - GFS input directory
#   COMINhrrr        - HRRR input directory
#   WGRIB2           - Path to wgrib2 executable
#   NDATE            - NDATE utility path
#
# Output Files:
#   ${DBASE}_forcing.nc - Combined forcing file with all timesteps
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
TIME_START=${3:-}
TIME_END=${4:-}

if [ -z "$DBASE" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "============================================"
    echo "Usage: $0 DBASE OUTPUT_DIR [TIME_START TIME_END]"
    echo ""
    echo "Arguments:"
    echo "  DBASE      - Data source: GFS25 or HRRR"
    echo "  OUTPUT_DIR - Directory for output files"
    echo "  TIME_START - Start time YYYYMMDDHH (optional)"
    echo "  TIME_END   - End time YYYYMMDDHH (optional)"
    echo ""
    echo "Environment Variables:"
    echo "  time_hotstart, time_forecastend, COMINgfs, COMINhrrr"
    echo "============================================"
    exit 1
fi

# =============================================================================
# Setup Environment
# =============================================================================
WGRIB2=${WGRIB2:-wgrib2}
NDATE=${NDATE:-ndate}

# Use environment time variables if arguments not provided
if [ -z "$TIME_START" ]; then
    if [ -n "$time_hotstart" ]; then
        # Go 3 hours before hotstart (same as sflux)
        TIME_START=$($NDATE -3 $time_hotstart)
    else
        echo "ERROR: TIME_START not provided and time_hotstart not set"
        exit 1
    fi
fi

if [ -z "$TIME_END" ]; then
    if [ -n "$time_forecastend" ]; then
        TIME_END=$time_forecastend
    else
        echo "ERROR: TIME_END not provided and time_forecastend not set"
        exit 1
    fi
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
TOTAL_HOURS=$($NHOUR $TIME_END $TIME_START 2>/dev/null || echo "54")

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
    # GFS 0.25 degree - 3-hourly forecasts
    INTERVAL=3
    COMIN=${COMINgfs:-/lfs/h1/ops/prod/com/gfs/v16.3}
    # Variables to extract
    MATCH_PATTERN=":(UGRD|VGRD):10 m above ground:|:(TMP|SPFH):2 m above ground:|:PRMSL:mean sea level:|:(DSWRF|DLWRF|PRATE):surface:"
    OUTPUT_FILE="${OUTPUT_DIR}/${DBASE_LOWER}_forcing.nc"

elif [ "$DBASE_UPPER" == "HRRR" ]; then
    # HRRR 3km - hourly forecasts
    INTERVAL=1
    COMIN=${COMINhrrr:-/lfs/h1/ops/prod/com/hrrr/v4.1}
    # HRRR uses MSLMA instead of PRMSL
    MATCH_PATTERN=":(UGRD|VGRD):10 m above ground:|:(TMP|SPFH):2 m above ground:|:MSLMA:mean sea level:|:(DSWRF|DLWRF|PRATE):surface:"
    OUTPUT_FILE="${OUTPUT_DIR}/${DBASE_LOWER}_forcing.nc"
else
    echo "ERROR: Unknown DBASE: $DBASE"
    echo "Supported values: GFS, GFS25, HRRR"
    exit 1
fi

# =============================================================================
# Step 1: Find and extract GRIB2 files for time range
# =============================================================================
# This mimics sflux logic: search across multiple cycles to cover the time range
echo ""
echo "Step 1: Finding GRIB2 files for time range..."
echo "============================================"

FILE_COUNT=0
MISSING_COUNT=0

# Current time pointer
CURRENT_TIME=$TIME_START

while [ $CURRENT_TIME -le $TIME_END ]; do
    # Extract date components
    YYYY=$(echo $CURRENT_TIME | cut -c1-4)
    MM=$(echo $CURRENT_TIME | cut -c5-6)
    DD=$(echo $CURRENT_TIME | cut -c7-8)
    HH=$(echo $CURRENT_TIME | cut -c9-10)

    # Find which cycle this time belongs to
    # GFS cycles: 00, 06, 12, 18
    # HRRR cycles: every hour

    if [ "$DBASE_UPPER" == "GFS" ] || [ "$DBASE_UPPER" == "GFS25" ]; then
        # Find nearest GFS cycle (00, 06, 12, 18)
        HH_NUM=$((10#$HH))
        if [ $HH_NUM -lt 6 ]; then
            CYCLE="00"
            CYCLE_DATE="${YYYY}${MM}${DD}"
        elif [ $HH_NUM -lt 12 ]; then
            CYCLE="06"
            CYCLE_DATE="${YYYY}${MM}${DD}"
        elif [ $HH_NUM -lt 18 ]; then
            CYCLE="12"
            CYCLE_DATE="${YYYY}${MM}${DD}"
        else
            CYCLE="18"
            CYCLE_DATE="${YYYY}${MM}${DD}"
        fi

        # Calculate forecast hour from cycle
        CYCLE_TIME="${CYCLE_DATE}${CYCLE}"
        FHR=$($NHOUR $CURRENT_TIME $CYCLE_TIME 2>/dev/null || echo "0")

        # If FHR is negative, use previous cycle
        if [ $FHR -lt 0 ]; then
            CYCLE_TIME=$($NDATE -6 $CYCLE_TIME)
            CYCLE_DATE=$(echo $CYCLE_TIME | cut -c1-8)
            CYCLE=$(echo $CYCLE_TIME | cut -c9-10)
            FHR=$($NHOUR $CURRENT_TIME $CYCLE_TIME 2>/dev/null || echo "0")
        fi

        FHR_STR=$(printf "%03d" $FHR)
        GRIB2_FILE="${COMIN}/gfs.${CYCLE_DATE}/${CYCLE}/atmos/gfs.t${CYCLE}z.pgrb2.0p25.f${FHR_STR}"

    else  # HRRR
        # HRRR has hourly cycles, but we prefer cycles with longer forecasts (00,06,12,18)
        HH_NUM=$((10#$HH))

        # Try current hour cycle first, then fall back to main cycles
        for TRY_CYCLE in $HH 00 06 12 18; do
            TRY_CYCLE=$(printf "%02d" $((10#$TRY_CYCLE)))
            CYCLE_DATE="${YYYY}${MM}${DD}"
            CYCLE_TIME="${CYCLE_DATE}${TRY_CYCLE}"

            FHR=$($NHOUR $CURRENT_TIME $CYCLE_TIME 2>/dev/null || echo "-1")

            # Check if FHR is valid (0-48 for main cycles, 0-18 for others)
            if [ $FHR -ge 0 ]; then
                if [ "$TRY_CYCLE" == "00" ] || [ "$TRY_CYCLE" == "06" ] || [ "$TRY_CYCLE" == "12" ] || [ "$TRY_CYCLE" == "18" ]; then
                    MAX_FHR=48
                else
                    MAX_FHR=18
                fi

                if [ $FHR -le $MAX_FHR ]; then
                    CYCLE=$TRY_CYCLE
                    break
                fi
            fi
        done

        # If still negative, try previous day's cycles
        if [ $FHR -lt 0 ] || [ $FHR -gt 48 ]; then
            PREV_DATE=$($NDATE -24 ${CYCLE_DATE}00 | cut -c1-8)
            for TRY_CYCLE in 18 12 06 00; do
                CYCLE_TIME="${PREV_DATE}${TRY_CYCLE}"
                FHR=$($NHOUR $CURRENT_TIME $CYCLE_TIME 2>/dev/null || echo "-1")
                if [ $FHR -ge 0 ] && [ $FHR -le 48 ]; then
                    CYCLE_DATE=$PREV_DATE
                    CYCLE=$TRY_CYCLE
                    break
                fi
            done
        fi

        FHR_STR=$(printf "%02d" $FHR)
        GRIB2_FILE="${COMIN}/hrrr.${CYCLE_DATE}/conus/hrrr.t${CYCLE}z.wrfsfcf${FHR_STR}.grib2"
    fi

    # Output file for this timestep
    TIME_STR="${YYYY}${MM}${DD}${HH}"
    NC_FILE="${TEMP_DIR}/${DBASE_LOWER}_${TIME_STR}.nc"

    if [ -s "$GRIB2_FILE" ]; then
        echo "Processing ${TIME_STR}: $GRIB2_FILE (f${FHR_STR})"

        $WGRIB2 $GRIB2_FILE \
            -match "$MATCH_PATTERN" \
            -netcdf $NC_FILE 2>/dev/null

        if [ -s "$NC_FILE" ]; then
            FILE_COUNT=$((FILE_COUNT + 1))
        else
            echo "WARNING: Failed to extract from $GRIB2_FILE"
            MISSING_COUNT=$((MISSING_COUNT + 1))
        fi
    else
        echo "WARNING: File not found: $GRIB2_FILE"
        MISSING_COUNT=$((MISSING_COUNT + 1))
    fi

    # Advance to next time step
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
# Step 2: Concatenate all files along time dimension
# =============================================================================
echo ""
echo "Step 2: Concatenating files..."
echo "============================================"

# List files in chronological order
NC_FILES=$(ls -1 ${TEMP_DIR}/${DBASE_LOWER}_*.nc 2>/dev/null | sort)
NUM_FILES=$(echo "$NC_FILES" | wc -l)

echo "Found $NUM_FILES NetCDF files to concatenate"

if [ -z "$NC_FILES" ]; then
    echo "ERROR: No NetCDF files found to concatenate"
    rm -rf $TEMP_DIR
    exit 1
fi

# Check for ncrcat (NCO)
if command -v ncrcat &> /dev/null; then
    echo "Using NCO ncrcat for concatenation..."
    ncrcat -O $NC_FILES ${OUTPUT_DIR}/${DBASE_LOWER}_forcing_raw.nc
    CONCAT_STATUS=$?
else
    echo "WARNING: ncrcat not found, trying Python..."

    # Unset LD_PRELOAD for Python
    SAVE_LD_PRELOAD=$LD_PRELOAD
    unset LD_PRELOAD

    python3 << EOF
import xarray as xr
import glob
import os

temp_dir = "${TEMP_DIR}"
output_file = "${OUTPUT_DIR}/${DBASE_LOWER}_forcing_raw.nc"
pattern = os.path.join(temp_dir, "${DBASE_LOWER}_*.nc")

files = sorted(glob.glob(pattern))
print(f"Concatenating {len(files)} files...")

if files:
    ds = xr.open_mfdataset(files, combine='by_coords')
    ds.to_netcdf(output_file)
    print(f"Created: {output_file}")
else:
    print("ERROR: No files found")
    exit(1)
EOF
    CONCAT_STATUS=$?
    export LD_PRELOAD=$SAVE_LD_PRELOAD
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

# Copy to final output file
cp ${OUTPUT_DIR}/${DBASE_LOWER}_forcing_raw.nc $OUTPUT_FILE

# Add global attributes using ncatted if available
if command -v ncatted &> /dev/null; then
    ncatted -h -a Conventions,global,o,c,"CF-1.6" $OUTPUT_FILE
    ncatted -h -a title,global,o,c,"${DBASE_UPPER} forcing data for UFS-Coastal DATM" $OUTPUT_FILE
    ncatted -h -a source,global,o,c,"NCEP ${DBASE_UPPER}" $OUTPUT_FILE
    ncatted -h -a institution,global,o,c,"NOAA/NOS/OCS" $OUTPUT_FILE
    ncatted -h -a history,global,o,c,"Created by nos_ofs_create_datm_forcing.sh on $(date)" $OUTPUT_FILE

    # Add coordinate attributes
    ncatted -h -a units,longitude,o,c,"degrees_east" $OUTPUT_FILE 2>/dev/null
    ncatted -h -a axis,longitude,o,c,"X" $OUTPUT_FILE 2>/dev/null
    ncatted -h -a standard_name,longitude,o,c,"longitude" $OUTPUT_FILE 2>/dev/null

    ncatted -h -a units,latitude,o,c,"degrees_north" $OUTPUT_FILE 2>/dev/null
    ncatted -h -a axis,latitude,o,c,"Y" $OUTPUT_FILE 2>/dev/null
    ncatted -h -a standard_name,latitude,o,c,"latitude" $OUTPUT_FILE 2>/dev/null

    ncatted -h -a axis,time,o,c,"T" $OUTPUT_FILE 2>/dev/null
fi

echo "Created: $OUTPUT_FILE"

# =============================================================================
# Step 4: Verify output
# =============================================================================
echo ""
echo "Step 4: Verifying output..."
echo "============================================"

# Get time dimension info
if command -v ncdump &> /dev/null; then
    TIME_STEPS=$(ncdump -h $OUTPUT_FILE | grep "time = " | head -1 | sed 's/.*time = \([0-9]*\).*/\1/')
else
    TIME_STEPS="unknown"
fi
FILE_SIZE=$(ls -lh $OUTPUT_FILE | awk '{print $5}')

echo "Output file: $OUTPUT_FILE"
echo "File size:   $FILE_SIZE"
echo "Time steps:  $TIME_STEPS"
echo ""

# Show variables if ncdump available
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
