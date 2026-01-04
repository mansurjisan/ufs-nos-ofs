#!/bin/bash
# =============================================================================
# Script Name: nos_ofs_create_datm_forcing.sh
#
# Purpose:
#   Create DATM forcing files by extracting and concatenating meteorological
#   variables from GFS/HRRR GRIB2 files for all forecast hours.
#   This creates time-series NetCDF files for use with UFS-Coastal CDEPS DATM.
#
# Usage:
#   ./nos_ofs_create_datm_forcing.sh DBASE OUTPUT_DIR
#
# Arguments:
#   DBASE      - Data source: GFS25 or HRRR
#   OUTPUT_DIR - Directory for output files
#
# Environment Variables:
#   PDY        - Forecast date (YYYYMMDD)
#   cyc        - Forecast cycle (00, 06, 12, 18)
#   NHOURS     - Forecast length in hours (default: 48)
#   COMINgfs   - GFS input directory
#   COMINhrrr  - HRRR input directory
#   WGRIB2     - Path to wgrib2 executable
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

if [ -z "$DBASE" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "============================================"
    echo "Usage: $0 DBASE OUTPUT_DIR"
    echo ""
    echo "Arguments:"
    echo "  DBASE      - Data source: GFS25 or HRRR"
    echo "  OUTPUT_DIR - Directory for output files"
    echo ""
    echo "Environment Variables Required:"
    echo "  PDY, cyc, NHOURS, COMINgfs/COMINhrrr"
    echo "============================================"
    exit 1
fi

# =============================================================================
# Setup Environment
# =============================================================================
WGRIB2=${WGRIB2:-wgrib2}
PDY=${PDY:-$(date +%Y%m%d)}
cyc=${cyc:-00}
NHOURS=${NHOURS:-48}

mkdir -p $OUTPUT_DIR
TEMP_DIR=${OUTPUT_DIR}/temp_forcing_$$
mkdir -p $TEMP_DIR

# Normalize DBASE
DBASE_UPPER=$(echo $DBASE | tr '[:lower:]' '[:upper:]')
DBASE_LOWER=$(echo $DBASE | tr '[:upper:]' '[:lower:]')
if [ "$DBASE_LOWER" == "gfs25" ]; then
    DBASE_LOWER="gfs"
fi

echo "============================================"
echo "DATM Forcing File Generation"
echo "============================================"
echo "DBASE:      $DBASE_UPPER"
echo "PDY:        $PDY"
echo "cyc:        $cyc"
echo "NHOURS:     $NHOURS"
echo "OUTPUT_DIR: $OUTPUT_DIR"
echo "TEMP_DIR:   $TEMP_DIR"
echo "============================================"

# =============================================================================
# Set Data Source Parameters
# =============================================================================
if [ "$DBASE_UPPER" == "GFS" ] || [ "$DBASE_UPPER" == "GFS25" ]; then
    # GFS 0.25 degree - 3-hourly forecasts
    INTERVAL=3
    COMIN=${COMINgfs:-/lfs/h1/ops/prod/com/gfs/v16.3}
    FILE_PATTERN="${COMIN}/gfs.${PDY}/${cyc}/atmos/gfs.t${cyc}z.pgrb2.0p25.f"
    MATCH_PATTERN=":(UGRD|VGRD):10 m above ground:|:(TMP|SPFH):2 m above ground:|:PRMSL:mean sea level:|:(DSWRF|DLWRF|PRATE):surface:"
    OUTPUT_FILE="${OUTPUT_DIR}/${DBASE_LOWER}_forcing.nc"

elif [ "$DBASE_UPPER" == "HRRR" ]; then
    # HRRR 3km - hourly forecasts (up to 18 or 48 hours depending on cycle)
    INTERVAL=1
    COMIN=${COMINhrrr:-/lfs/h1/ops/prod/com/hrrr/v4.1}
    FILE_PATTERN="${COMIN}/hrrr.${PDY}/conus/hrrr.t${cyc}z.wrfsfcf"
    # HRRR uses MSLMA instead of PRMSL
    MATCH_PATTERN=":(UGRD|VGRD):10 m above ground:|:(TMP|SPFH):2 m above ground:|:MSLMA:mean sea level:|:(DSWRF|DLWRF|PRATE):surface:"
    OUTPUT_FILE="${OUTPUT_DIR}/${DBASE_LOWER}_forcing.nc"
    # HRRR max forecast hours varies by cycle
    if [ "$cyc" == "00" ] || [ "$cyc" == "06" ] || [ "$cyc" == "12" ] || [ "$cyc" == "18" ]; then
        HRRR_MAX_HOURS=48
    else
        HRRR_MAX_HOURS=18
    fi
    if [ $NHOURS -gt $HRRR_MAX_HOURS ]; then
        echo "WARNING: HRRR max forecast for cycle $cyc is $HRRR_MAX_HOURS hours"
        echo "         Limiting to $HRRR_MAX_HOURS hours"
        NHOURS=$HRRR_MAX_HOURS
    fi
else
    echo "ERROR: Unknown DBASE: $DBASE"
    echo "Supported values: GFS, GFS25, HRRR"
    exit 1
fi

# =============================================================================
# Step 1: Extract variables from each forecast hour
# =============================================================================
echo ""
echo "Step 1: Extracting variables from GRIB2 files..."
echo "============================================"

FILE_COUNT=0
MISSING_COUNT=0

for fhr in $(seq 0 $INTERVAL $NHOURS); do
    # Format forecast hour with leading zeros
    if [ "$DBASE_UPPER" == "HRRR" ]; then
        FHR_STR=$(printf "%02d" $fhr)
        GRIB2_FILE="${FILE_PATTERN}${FHR_STR}.grib2"
    else
        FHR_STR=$(printf "%03d" $fhr)
        GRIB2_FILE="${FILE_PATTERN}${FHR_STR}"
    fi

    NC_FILE="${TEMP_DIR}/${DBASE_LOWER}_f${FHR_STR}.nc"

    if [ -s "$GRIB2_FILE" ]; then
        echo "Processing f${FHR_STR}: $GRIB2_FILE"

        $WGRIB2 $GRIB2_FILE \
            -match "$MATCH_PATTERN" \
            -netcdf $NC_FILE

        if [ -s "$NC_FILE" ]; then
            FILE_COUNT=$((FILE_COUNT + 1))
        else
            echo "WARNING: Failed to create $NC_FILE"
        fi
    else
        echo "WARNING: File not found: $GRIB2_FILE"
        MISSING_COUNT=$((MISSING_COUNT + 1))
    fi
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

# Check for ncrcat (NCO)
if command -v ncrcat &> /dev/null; then
    echo "Using NCO ncrcat for concatenation..."

    # List files in order
    NC_FILES=$(ls -1 ${TEMP_DIR}/${DBASE_LOWER}_f*.nc 2>/dev/null | sort)

    if [ -n "$NC_FILES" ]; then
        ncrcat -O $NC_FILES ${OUTPUT_DIR}/${DBASE_LOWER}_forcing_raw.nc
        CONCAT_STATUS=$?
    else
        echo "ERROR: No NetCDF files found to concatenate"
        rm -rf $TEMP_DIR
        exit 1
    fi
else
    echo "WARNING: ncrcat not found, trying Python..."

    # Use Python xarray for concatenation
    python3 << EOF
import xarray as xr
import glob
import os

temp_dir = "${TEMP_DIR}"
output_file = "${OUTPUT_DIR}/${DBASE_LOWER}_forcing_raw.nc"
pattern = os.path.join(temp_dir, "${DBASE_LOWER}_f*.nc")

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

# Add global attributes
ncatted -h -a Conventions,global,o,c,"CF-1.6" $OUTPUT_FILE
ncatted -h -a title,global,o,c,"${DBASE_UPPER} forcing data for UFS-Coastal DATM" $OUTPUT_FILE
ncatted -h -a source,global,o,c,"NCEP ${DBASE_UPPER}" $OUTPUT_FILE
ncatted -h -a history,global,o,c,"Created by nos_ofs_create_datm_forcing.sh on $(date)" $OUTPUT_FILE

# Add coordinate attributes
ncatted -h -a units,longitude,o,c,"degrees_east" $OUTPUT_FILE
ncatted -h -a axis,longitude,o,c,"X" $OUTPUT_FILE
ncatted -h -a standard_name,longitude,o,c,"longitude" $OUTPUT_FILE

ncatted -h -a units,latitude,o,c,"degrees_north" $OUTPUT_FILE
ncatted -h -a axis,latitude,o,c,"Y" $OUTPUT_FILE
ncatted -h -a standard_name,latitude,o,c,"latitude" $OUTPUT_FILE

ncatted -h -a axis,time,o,c,"T" $OUTPUT_FILE

echo "Created: $OUTPUT_FILE"

# =============================================================================
# Step 4: Verify output
# =============================================================================
echo ""
echo "Step 4: Verifying output..."
echo "============================================"

# Get time dimension info
TIME_STEPS=$(ncdump -h $OUTPUT_FILE | grep "time = " | head -1 | sed 's/.*time = \([0-9]*\).*/\1/')
FILE_SIZE=$(ls -lh $OUTPUT_FILE | awk '{print $5}')

echo "Output file: $OUTPUT_FILE"
echo "File size:   $FILE_SIZE"
echo "Time steps:  $TIME_STEPS"
echo ""

# Show variables
echo "Variables:"
ncdump -h $OUTPUT_FILE | grep -E "^\s+(float|double)" | head -10

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
echo "Time steps: $TIME_STEPS"
echo "============================================"

exit 0
