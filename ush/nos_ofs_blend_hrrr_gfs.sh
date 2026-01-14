#!/bin/bash
# =============================================================================
# Script Name: nos_ofs_blend_hrrr_gfs.sh
#
# Purpose:
#   Blend HRRR and GFS forcing files into a single NetCDF for CDEPS/DATM.
#   - Uses HRRR data where available (CONUS, ~21°N to 53°N)
#   - Fills gaps with GFS data (Caribbean, Puerto Rico, open ocean)
#   - Preserves HRRR's native ~3km resolution (0.025°)
#
# Usage:
#   ./nos_ofs_blend_hrrr_gfs.sh HRRR_FILE GFS_FILE OUTPUT_FILE [DOMAIN]
#
# Arguments:
#   HRRR_FILE   - Input HRRR forcing NetCDF file
#   GFS_FILE    - Input GFS forcing NetCDF file
#   OUTPUT_FILE - Output blended NetCDF file
#   DOMAIN      - Domain preset: ATLANTIC (default), SECOFS, STOFS3D_ATL
#
# Domain Presets:
#   ATLANTIC:    10°N-53°N, 98°W-55°W (full Atlantic basin + PR)
#   SECOFS:      23°N-37°N, 82°W-73°W (Southeast coast)
#   STOFS3D_ATL: 7°N-53°N, 99°W-52°W (STOFS-3D Atlantic domain)
#
# Environment Variables:
#   RESOLUTION - Grid resolution in degrees (default: 0.025)
#
# Author: SECOFS UFS-Coastal Transition
# Date: January 2026
# =============================================================================

set -eu

# =============================================================================
# Load Python Module (WCOSS2)
# =============================================================================
if command -v module &> /dev/null; then
    module load python/3.12.0 2>/dev/null || true
fi

# =============================================================================
# Parse Arguments
# =============================================================================
HRRR_FILE=$1
GFS_FILE=$2
OUTPUT_FILE=$3
DOMAIN=${4:-ATLANTIC}

if [ -z "$HRRR_FILE" ] || [ -z "$GFS_FILE" ] || [ -z "$OUTPUT_FILE" ]; then
    echo "Usage: $0 HRRR_FILE GFS_FILE OUTPUT_FILE [DOMAIN]"
    echo ""
    echo "Domain presets: ATLANTIC, SECOFS, STOFS3D_ATL"
    exit 1
fi

# Resolution (match HRRR native ~3km)
RESOLUTION=${RESOLUTION:-0.025}

# Verify inputs exist
if [ ! -s "$HRRR_FILE" ]; then
    echo "ERROR: HRRR file not found: $HRRR_FILE"
    exit 1
fi
if [ ! -s "$GFS_FILE" ]; then
    echo "ERROR: GFS file not found: $GFS_FILE"
    exit 1
fi

# =============================================================================
# Run Python blending script
# =============================================================================
OUTPUT_DIR=$(dirname $OUTPUT_FILE)
mkdir -p $OUTPUT_DIR

# Find the Python blending script
USHnos=${USHnos:-$(dirname $0)}
BLEND_PY="${USHnos}/blend_hrrr_gfs.py"

if [ ! -s "$BLEND_PY" ]; then
    echo "ERROR: Python blending script not found: $BLEND_PY"
    exit 1
fi

echo "Running: python $BLEND_PY $HRRR_FILE $GFS_FILE $OUTPUT_FILE $DOMAIN $RESOLUTION"
python $BLEND_PY $HRRR_FILE $GFS_FILE $OUTPUT_FILE $DOMAIN $RESOLUTION
BLEND_STATUS=$?

if [ $BLEND_STATUS -ne 0 ]; then
    echo "ERROR: Blending failed with status $BLEND_STATUS"
    exit 1
fi

# Check output
if [ ! -s "$OUTPUT_FILE" ]; then
    echo "ERROR: Blending failed - output file not created"
    exit 1
fi

FILE_SIZE=$(ls -lh $OUTPUT_FILE | awk '{print $5}')
echo ""
echo "============================================"
echo "Step 1/3: Blending COMPLETED"
echo "============================================"
echo "Output: $OUTPUT_FILE"
echo "Size:   $FILE_SIZE"

# =============================================================================
# Step 2: Generate SCRIP Grid
# =============================================================================
echo ""
echo "============================================"
echo "Step 2/3: Generating SCRIP grid..."
echo "============================================"

BASENAME=$(basename $OUTPUT_FILE .nc)
SCRIP_FILE="${OUTPUT_DIR}/${BASENAME}_scrip.nc"

# Find proc_scrip.py
SCRIP_SCRIPT="${USHnos}/pysh/proc_scrip.py"

if [ ! -s "$SCRIP_SCRIPT" ]; then
    # Try alternate location
    SCRIP_SCRIPT="$(dirname $0)/pysh/proc_scrip.py"
fi

if [ -s "$SCRIP_SCRIPT" ]; then
    python $SCRIP_SCRIPT --ifile $OUTPUT_FILE --ofile $(basename $SCRIP_FILE) --odir $OUTPUT_DIR
    SCRIP_STATUS=$?
else
    echo "WARNING: proc_scrip.py not found at $SCRIP_SCRIPT"
    SCRIP_STATUS=1
fi

if [ -s "$SCRIP_FILE" ]; then
    echo "SCRIP file created: $SCRIP_FILE"
    echo "Size: $(ls -lh $SCRIP_FILE | awk '{print $5}')"
else
    echo "WARNING: SCRIP generation failed"
    echo "You can generate it manually with:"
    echo "  python proc_scrip.py --ifile $OUTPUT_FILE --ofile ${BASENAME}_scrip.nc"
fi

# =============================================================================
# Step 3: Generate ESMF Mesh (if ESMF_Scrip2Unstruct available)
# =============================================================================
echo ""
echo "============================================"
echo "Step 3/3: Generating ESMF mesh..."
echo "============================================"

MESH_FILE="${OUTPUT_DIR}/${BASENAME}_esmf_mesh.nc"

ESMF_CMD=""
if command -v ESMF_Scrip2Unstruct &> /dev/null; then
    ESMF_CMD="ESMF_Scrip2Unstruct"
elif command -v conda &> /dev/null && conda run -n ncl_env which ESMF_Scrip2Unstruct &> /dev/null; then
    ESMF_CMD="conda run -n ncl_env ESMF_Scrip2Unstruct"
fi

if [ -n "$ESMF_CMD" ]; then
    if [ -s "$SCRIP_FILE" ]; then
        $ESMF_CMD $SCRIP_FILE $MESH_FILE 0
        if [ -s "$MESH_FILE" ]; then
            echo "ESMF mesh created: $MESH_FILE"
            echo "Size: $(ls -lh $MESH_FILE | awk '{print $5}')"
        else
            echo "WARNING: ESMF mesh generation failed"
        fi
    else
        echo "WARNING: Cannot generate ESMF mesh - SCRIP file missing"
    fi
else
    echo "ESMF_Scrip2Unstruct not available (requires ESMF module)"
    echo ""
    echo "To generate ESMF mesh on WCOSS2:"
    echo "  module load esmf"
    echo "  ESMF_Scrip2Unstruct $SCRIP_FILE $MESH_FILE 0"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "============================================"
echo "BLENDING WORKFLOW COMPLETED"
echo "============================================"
echo ""
echo "Output files:"
echo "  Forcing:    $OUTPUT_FILE"
[ -s "$SCRIP_FILE" ] && echo "  SCRIP:      $SCRIP_FILE"
[ -s "$MESH_FILE" ] && echo "  ESMF Mesh:  $MESH_FILE"
echo ""
echo "For DATM configuration, update datm_in with:"
echo "  nx_global = $(ncdump -h $OUTPUT_FILE 2>/dev/null | grep "x = " | sed 's/.*x = \([0-9]*\).*/\1/' || echo "CHECK")"
echo "  ny_global = $(ncdump -h $OUTPUT_FILE 2>/dev/null | grep "y = " | sed 's/.*y = \([0-9]*\).*/\1/' || echo "CHECK")"
echo "============================================"
