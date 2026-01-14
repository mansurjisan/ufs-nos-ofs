#!/bin/bash
# =============================================================================
# Script Name: nos_ofs_create_datm_forcing_blended.sh
#
# Purpose:
#   Generate blended HRRR+GFS forcing for CDEPS/DATM in UFS-Coastal.
#   This is a wrapper script that:
#     1. Generates HRRR forcing (nos_ofs_create_datm_forcing.sh HRRR)
#     2. Generates GFS forcing (nos_ofs_create_datm_forcing.sh GFS25)
#     3. Blends HRRR+GFS (nos_ofs_blend_hrrr_gfs.sh)
#     4. Copies files to INPUT directory
#
# Usage:
#   ./nos_ofs_create_datm_forcing_blended.sh [DOMAIN]
#
# Arguments:
#   DOMAIN - Domain preset: ATLANTIC (default), SECOFS, STOFS3D_ATL
#
# Environment Variables (required):
#   PDY        - Forecast date (YYYYMMDD)
#   cyc        - Forecast cycle (00, 06, 12, 18)
#   DATA       - Working directory
#   COMINgfs   - GFS input directory
#   COMINhrrr  - HRRR input directory
#
# Environment Variables (optional):
#   time_hotstart    - Start time (default: PDYcyc - 6h)
#   time_nowcastend  - Nowcast end time (default: PDYcyc)
#   time_forecastend - Forecast end time (default: PDYcyc + 48h)
#   RESOLUTION       - Grid resolution in degrees (default: 0.025)
#
# Output Files:
#   $DATA/INPUT/atlantic_forcing.nc      - Blended forcing file
#   $DATA/INPUT/atlantic_esmf_mesh.nc    - ESMF mesh file
#
# Called by:
#   exnos_ofs_prep.sh (when USE_DATM=1 and DATM_BLEND_HRRR_GFS=1)
#
# Author: SECOFS UFS-Coastal Transition
# Date: January 2026
# =============================================================================

set -x

# =============================================================================
# Parse Arguments
# =============================================================================
DOMAIN=${1:-ATLANTIC}

# =============================================================================
# Setup Environment
# =============================================================================
USHnos=${USHnos:-$(dirname $0)}
NDATE=${NDATE:-ndate}
NHOUR=${NHOUR:-nhour}

PDY=${PDY:-$(date +%Y%m%d)}
cyc=${cyc:-00}
DATA=${DATA:-$(pwd)}

# Time range defaults
time_hotstart=${time_hotstart:-$($NDATE -6 ${PDY}${cyc})}
time_nowcastend=${time_nowcastend:-${PDY}${cyc}}
time_forecastend=${time_forecastend:-$($NDATE 48 ${PDY}${cyc})}

# Export for sub-scripts
export PDY cyc DATA time_hotstart time_nowcastend time_forecastend

# Working directories
DATM_WORK=${DATA}/datm_forcing
mkdir -p $DATM_WORK
mkdir -p ${DATA}/INPUT

echo "============================================"
echo "DATM Blended Forcing Generation"
echo "============================================"
echo "PDY:              $PDY"
echo "cyc:              $cyc"
echo "Domain:           $DOMAIN"
echo "time_hotstart:    $time_hotstart"
echo "time_nowcastend:  $time_nowcastend"
echo "time_forecastend: $time_forecastend"
echo "DATA:             $DATA"
echo "DATM_WORK:        $DATM_WORK"
echo "============================================"

# =============================================================================
# Step 1: Generate HRRR Forcing
# =============================================================================
echo ""
echo "============================================"
echo "Step 1/4: Generating HRRR forcing..."
echo "============================================"

TIME_START=$($NDATE -3 $time_hotstart)  # 3h buffer before hotstart
TIME_END=$time_forecastend

$USHnos/nos_ofs_create_datm_forcing.sh HRRR $DATM_WORK $TIME_START $TIME_END
HRRR_STATUS=$?

if [ $HRRR_STATUS -ne 0 ] || [ ! -s "$DATM_WORK/hrrr_forcing.nc" ]; then
    echo "ERROR: HRRR forcing generation failed"
    exit 1
fi
echo "HRRR forcing created: $DATM_WORK/hrrr_forcing.nc"

# =============================================================================
# Step 2: Generate GFS Forcing
# =============================================================================
echo ""
echo "============================================"
echo "Step 2/4: Generating GFS forcing..."
echo "============================================"

$USHnos/nos_ofs_create_datm_forcing.sh GFS25 $DATM_WORK $TIME_START $TIME_END
GFS_STATUS=$?

if [ $GFS_STATUS -ne 0 ] || [ ! -s "$DATM_WORK/gfs_forcing.nc" ]; then
    echo "ERROR: GFS forcing generation failed"
    exit 1
fi
echo "GFS forcing created: $DATM_WORK/gfs_forcing.nc"

# =============================================================================
# Step 3: Blend HRRR + GFS
# =============================================================================
echo ""
echo "============================================"
echo "Step 3/4: Blending HRRR + GFS..."
echo "============================================"

# Output file name based on domain
case $DOMAIN in
    ATLANTIC)    BLEND_NAME="atlantic_forcing.nc" ;;
    SECOFS)      BLEND_NAME="secofs_forcing.nc" ;;
    STOFS3D_ATL) BLEND_NAME="stofs3d_forcing.nc" ;;
    *)           BLEND_NAME="blended_forcing.nc" ;;
esac

$USHnos/nos_ofs_blend_hrrr_gfs.sh \
    $DATM_WORK/hrrr_forcing.nc \
    $DATM_WORK/gfs_forcing.nc \
    $DATM_WORK/$BLEND_NAME \
    $DOMAIN

BLEND_STATUS=$?

if [ $BLEND_STATUS -ne 0 ] || [ ! -s "$DATM_WORK/$BLEND_NAME" ]; then
    echo "ERROR: Blending failed"
    exit 1
fi

# =============================================================================
# Step 4: Copy to INPUT Directory
# =============================================================================
echo ""
echo "============================================"
echo "Step 4/4: Copying to INPUT directory..."
echo "============================================"

# Get base name without .nc extension
BASENAME=$(basename $BLEND_NAME .nc)

# Copy forcing file
cp $DATM_WORK/$BLEND_NAME ${DATA}/INPUT/
echo "Copied: ${DATA}/INPUT/$BLEND_NAME"

# Copy ESMF mesh if generated
MESH_FILE="$DATM_WORK/${BASENAME}_esmf_mesh.nc"
if [ -s "$MESH_FILE" ]; then
    cp $MESH_FILE ${DATA}/INPUT/
    echo "Copied: ${DATA}/INPUT/${BASENAME}_esmf_mesh.nc"
else
    # Copy SCRIP file for manual ESMF mesh generation
    SCRIP_FILE="$DATM_WORK/${BASENAME}_scrip.nc"
    if [ -s "$SCRIP_FILE" ]; then
        cp $SCRIP_FILE ${DATA}/INPUT/
        echo "Copied: ${DATA}/INPUT/${BASENAME}_scrip.nc"
        echo ""
        echo "WARNING: ESMF mesh not generated (ESMF_Scrip2Unstruct not available)"
        echo "Generate manually with:"
        echo "  module load esmf"
        echo "  ESMF_Scrip2Unstruct ${DATA}/INPUT/${BASENAME}_scrip.nc ${DATA}/INPUT/${BASENAME}_esmf_mesh.nc 0"
    fi
fi

# =============================================================================
# Generate DATM Configuration Files
# =============================================================================
echo ""
echo "============================================"
echo "Generating DATM configuration files..."
echo "============================================"

YYYY=${PDY:0:4}

# Get grid dimensions from forcing file
if command -v ncdump &> /dev/null; then
    NX=$(ncdump -h $DATM_WORK/$BLEND_NAME 2>/dev/null | grep "x = " | sed 's/.*x = \([0-9]*\).*/\1/')
    NY=$(ncdump -h $DATM_WORK/$BLEND_NAME 2>/dev/null | grep "y = " | sed 's/.*y = \([0-9]*\).*/\1/')
else
    NX="CHECK"
    NY="CHECK"
fi

# Generate datm.streams
cat > ${DATA}/datm.streams << EOF
stream_info:               ${BASENAME}.01
taxmode01:                 limit
mapalgo01:                 redist
tInterpAlgo01:             linear
readMode01:                single
dtlimit01:                 1.5
stream_offset01:           0
yearFirst01:               ${YYYY}
yearLast01:                ${YYYY}
yearAlign01:               ${YYYY}
stream_vectors01:          null
stream_mesh_file01:        "INPUT/${BASENAME}_esmf_mesh.nc"
stream_lev_dimname01:      null
stream_data_files01:       "INPUT/${BLEND_NAME}"
stream_data_variables01:   "UGRD_10maboveground Sa_u10m" "VGRD_10maboveground Sa_v10m" "TMP_2maboveground Sa_tbot" "SPFH_2maboveground Sa_shum" "MSLMA_meansealevel Sa_pslv" "DSWRF_surface Faxa_swdn" "DLWRF_surface Faxa_lwdn" "PRATE_surface Faxa_rain"
EOF
echo "Created: ${DATA}/datm.streams"

# Generate datm_in
cat > ${DATA}/datm_in << EOF
&datm_nml
  datamode = "ATMMESH"
  factorfn_data = "null"
  factorfn_mesh = "null"
  flds_co2 = .false.
  flds_presaero = .false.
  flds_wiso = .false.
  iradsw = 1
  model_maskfile = "INPUT/${BASENAME}_esmf_mesh.nc"
  model_meshfile = "INPUT/${BASENAME}_esmf_mesh.nc"
  nx_global = ${NX}
  ny_global = ${NY}
  restfilm = "null"
  export_all = .true.
/
EOF
echo "Created: ${DATA}/datm_in"

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "============================================"
echo "DATM BLENDED FORCING GENERATION COMPLETED"
echo "============================================"
echo ""
echo "Output files in ${DATA}/INPUT/:"
ls -lh ${DATA}/INPUT/${BASENAME}* 2>/dev/null
echo ""
echo "Configuration files in ${DATA}/:"
ls -lh ${DATA}/datm.streams ${DATA}/datm_in 2>/dev/null
echo ""
echo "Grid dimensions: nx=${NX}, ny=${NY}"
echo "============================================"

exit 0
