#!/bin/bash
# =============================================================================
# Script Name: nos_ofs_create_esmf_mesh.sh
#
# Purpose:
#   Generate ESMF unstructured mesh files from GFS/HRRR GRIB2 data for use
#   with CDEPS DATM in UFS-Coastal.
#
# Usage:
#   ./nos_ofs_create_esmf_mesh.sh DBASE GRIB2_FILE OUTPUT_DIR
#
# Arguments:
#   DBASE      - Data source: GFS, GFS25, or HRRR
#   GRIB2_FILE - Path to input GRIB2 file
#   OUTPUT_DIR - Directory for output files
#
# Output Files:
#   ${DBASE}_raw.nc       - Raw NetCDF from wgrib2
#   ${DBASE}_for_esmf.nc  - NetCDF with ESMF/CF attributes
#   ${DBASE}_scrip.nc     - SCRIP format grid file
#   ${DBASE}_esmf_mesh.nc - Final ESMF unstructured mesh
#
# Dependencies:
#   - wgrib2 (GRIB2 processing)
#   - ESMF_Scrip2Unstruct (mesh creation)
#   - Python 3 with netCDF4, numpy, xarray
#
# Helper Scripts (in USHnos/pysh directory):
#   - modify_gfs_4_esmfmesh.py  (GFS CF attribute processing)
#   - modify_hrrr_4_esmfmesh.py (HRRR CF attribute processing)
#   - proc_scrip.py             (SCRIP grid generation - replaces NCL)
#
# Environment Variables:
#   WGRIB2   - Path to wgrib2 executable (default: wgrib2)
#   USHnos   - Path to USH scripts directory
#
# Author: Adapted for SECOFS UFS-Coastal transition
# Date: January 2026
# =============================================================================

set -x

# =============================================================================
# Parse Arguments
# =============================================================================
DBASE=$1
GRIB2_FILE=$2
OUTPUT_DIR=$3

if [ -z "$DBASE" ] || [ -z "$GRIB2_FILE" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "============================================"
    echo "ERROR: Missing required arguments"
    echo "============================================"
    echo "Usage: $0 DBASE GRIB2_FILE OUTPUT_DIR"
    echo ""
    echo "Arguments:"
    echo "  DBASE      - Data source: GFS, GFS25, or HRRR"
    echo "  GRIB2_FILE - Path to input GRIB2 file"
    echo "  OUTPUT_DIR - Directory for output files"
    echo ""
    echo "Example:"
    echo "  $0 GFS25 /path/to/gfs.t06z.pgrb2.0p25.f000 ./output"
    echo "  $0 HRRR /path/to/hrrr.t05z.wrfsfcf01.grib2 ./output"
    exit 1
fi

# =============================================================================
# Validate Input File
# =============================================================================
if [ ! -s "$GRIB2_FILE" ]; then
    echo "ERROR: Input GRIB2 file not found or empty: $GRIB2_FILE"
    exit 1
fi

# Safety check: prevent output dir from being same as input file directory
INPUT_DIR=$(dirname "$GRIB2_FILE")
if [ "$(realpath $OUTPUT_DIR 2>/dev/null)" == "$(realpath $INPUT_DIR 2>/dev/null)" ]; then
    echo "WARNING: OUTPUT_DIR is same as input file directory"
    echo "Creating subdirectory 'esmf_output' to avoid overwriting input files"
    OUTPUT_DIR="${OUTPUT_DIR}/esmf_output"
fi

# =============================================================================
# Setup Environment
# =============================================================================
WGRIB2=${WGRIB2:-wgrib2}
USHnos=${USHnos:-$(dirname $0)}

# Create output directory
mkdir -p $OUTPUT_DIR

# Set file names
DBASE_LOWER=$(echo $DBASE | tr '[:upper:]' '[:lower:]')
# Normalize GFS25 to gfs for file naming
if [ "$DBASE_LOWER" == "gfs25" ]; then
    DBASE_LOWER="gfs"
fi

RAW_NC="${OUTPUT_DIR}/${DBASE_LOWER}_raw.nc"
ESMF_NC="${OUTPUT_DIR}/${DBASE_LOWER}_for_esmf.nc"
SCRIP_NC="${OUTPUT_DIR}/${DBASE_LOWER}_scrip.nc"
MESH_NC="${OUTPUT_DIR}/${DBASE_LOWER}_esmf_mesh.nc"

echo "============================================"
echo "ESMF Mesh Generation for $DBASE"
echo "============================================"
echo "Input:      $GRIB2_FILE"
echo "Output Dir: $OUTPUT_DIR"
echo "Raw NC:     $RAW_NC"
echo "ESMF NC:    $ESMF_NC"
echo "SCRIP NC:   $SCRIP_NC"
echo "Mesh NC:    $MESH_NC"
echo "============================================"

# =============================================================================
# Step 1: Convert GRIB2 to NetCDF
# =============================================================================
echo ""
echo "Step 1: Converting GRIB2 to NetCDF..."
echo "============================================"

# Remove existing file
rm -f $RAW_NC

# Extract relevant variables based on data source
# NOTE: Multiple -match options are ANDed in wgrib2, so we use a single -match
#       with OR (|) to select all desired variables
if [ "$DBASE" == "GFS" ] || [ "$DBASE" == "GFS25" ]; then
    echo "Extracting GFS variables..."
    # Variables: UGRD/VGRD 10m, TMP/SPFH 2m, PRMSL, DSWRF/DLWRF/PRATE surface
    $WGRIB2 $GRIB2_FILE \
        -match ":(UGRD|VGRD):10 m above ground:|:(TMP|SPFH):2 m above ground:|:PRMSL:mean sea level:|:(DSWRF|DLWRF|PRATE):surface:" \
        -netcdf $RAW_NC

elif [ "$DBASE" == "HRRR" ]; then
    echo "Extracting HRRR variables..."
    # HRRR uses MSLMA instead of PRMSL for mean sea level pressure
    # Variables: UGRD/VGRD 10m, TMP/SPFH 2m, MSLMA, DSWRF/DLWRF/PRATE surface
    $WGRIB2 $GRIB2_FILE \
        -match ":(UGRD|VGRD):10 m above ground:|:(TMP|SPFH):2 m above ground:|:MSLMA:mean sea level:|:(DSWRF|DLWRF|PRATE):surface:" \
        -netcdf $RAW_NC
else
    echo "ERROR: Unknown DBASE: $DBASE"
    echo "Supported values: GFS, GFS25, HRRR"
    exit 1
fi

# Verify output
if [ ! -s $RAW_NC ]; then
    echo "ERROR: Failed to create $RAW_NC"
    echo "Check wgrib2 output and input GRIB2 file"
    exit 1
fi

echo "Created: $RAW_NC"
echo "File size: $(ls -lh $RAW_NC | awk '{print $5}')"

# =============================================================================
# Step 2: Add ESMF/CF Attributes
# =============================================================================
echo ""
echo "Step 2: Adding ESMF/CF attributes..."
echo "============================================"

# Check for Python preprocessing script (in pysh subdirectory)
MODIFY_SCRIPT="${USHnos}/pysh/modify_${DBASE_LOWER}_4_esmfmesh.py"
if [ ! -s "$MODIFY_SCRIPT" ]; then
    echo "ERROR: Preprocessing script not found: $MODIFY_SCRIPT"
    exit 1
fi

python3 $MODIFY_SCRIPT $RAW_NC $ESMF_NC

if [ ! -s $ESMF_NC ]; then
    echo "ERROR: Failed to create $ESMF_NC"
    exit 1
fi

echo "Created: $ESMF_NC"
echo "File size: $(ls -lh $ESMF_NC | awk '{print $5}')"

# =============================================================================
# Step 3: Generate SCRIP Grid (using Python - no NCL dependency)
# =============================================================================
echo ""
echo "Step 3: Generating SCRIP grid..."
echo "============================================"

# Check for Python SCRIP generation script (in pysh subdirectory)
SCRIP_SCRIPT="${USHnos}/pysh/proc_scrip.py"
if [ ! -s "$SCRIP_SCRIPT" ]; then
    echo "ERROR: Python SCRIP script not found: $SCRIP_SCRIPT"
    exit 1
fi

# Run Python to generate SCRIP grid
# This script handles both rectilinear (GFS) and curvilinear (HRRR) grids
python3 $SCRIP_SCRIPT --ifile $ESMF_NC --ofile $(basename $SCRIP_NC) --odir $OUTPUT_DIR

if [ ! -s $SCRIP_NC ]; then
    echo "ERROR: Failed to create $SCRIP_NC"
    exit 1
fi

echo "Created: $SCRIP_NC"
echo "File size: $(ls -lh $SCRIP_NC | awk '{print $5}')"

# =============================================================================
# Step 4: Create ESMF Unstructured Mesh
# =============================================================================
echo ""
echo "Step 4: Creating ESMF unstructured mesh..."
echo "============================================"

# Check for ESMF_Scrip2Unstruct
if ! command -v ESMF_Scrip2Unstruct &> /dev/null; then
    echo "ERROR: ESMF_Scrip2Unstruct not found in PATH"
    echo "Please load ESMF module or add to PATH"
    exit 1
fi

# Create ESMF mesh (0 = no dual mesh)
ESMF_Scrip2Unstruct $SCRIP_NC $MESH_NC 0

if [ ! -s $MESH_NC ]; then
    echo "ERROR: Failed to create $MESH_NC"
    exit 1
fi

echo "Created: $MESH_NC"
echo "File size: $(ls -lh $MESH_NC | awk '{print $5}')"

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "============================================"
echo "ESMF Mesh Generation COMPLETED SUCCESSFULLY"
echo "============================================"
echo ""
echo "Output files:"
echo "  Raw NetCDF:   $RAW_NC"
echo "  ESMF NetCDF:  $ESMF_NC"
echo "  SCRIP Grid:   $SCRIP_NC"
echo "  ESMF Mesh:    $MESH_NC"
echo ""
echo "Next steps:"
echo "  1. Copy $MESH_NC to \$FIXofs for caching"
echo "  2. Use with CDEPS DATM stream configuration"
echo ""
echo "============================================"

exit 0
