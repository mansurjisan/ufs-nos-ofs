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

# Domain bounds based on preset
case $DOMAIN in
    ATLANTIC)
        LON_MIN=-98.0; LON_MAX=-55.0
        LAT_MIN=10.0;  LAT_MAX=53.0
        ;;
    SECOFS)
        LON_MIN=-82.0; LON_MAX=-73.0
        LAT_MIN=23.0;  LAT_MAX=37.0
        ;;
    STOFS3D_ATL)
        LON_MIN=-99.0; LON_MAX=-52.0
        LAT_MIN=7.0;   LAT_MAX=53.0
        ;;
    *)
        echo "ERROR: Unknown domain: $DOMAIN"
        echo "Supported: ATLANTIC, SECOFS, STOFS3D_ATL"
        exit 1
        ;;
esac

echo "============================================"
echo "HRRR + GFS Blending for CDEPS/DATM"
echo "============================================"
echo "HRRR input:   $HRRR_FILE"
echo "GFS input:    $GFS_FILE"
echo "Output:       $OUTPUT_FILE"
echo "Domain:       $DOMAIN"
echo "Resolution:   ${RESOLUTION}°"
echo "Bounds:       ${LAT_MIN}°N-${LAT_MAX}°N, ${LON_MIN}°E-${LON_MAX}°E"
echo "============================================"

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

python3 << PYEOF
#!/usr/bin/env python3
"""
Blend HRRR and GFS forcing files for CDEPS/DATM.
Memory-optimized version for WCOSS2.
"""

import numpy as np
from netCDF4 import Dataset
from scipy.spatial import cKDTree
from scipy.interpolate import RegularGridInterpolator, interp1d
from datetime import datetime
import sys
import gc

# Configuration from shell
HRRR_FILE = "${HRRR_FILE}"
GFS_FILE = "${GFS_FILE}"
OUTPUT_FILE = "${OUTPUT_FILE}"
TARGET_LON_MIN, TARGET_LON_MAX = ${LON_MIN}, ${LON_MAX}
TARGET_LAT_MIN, TARGET_LAT_MAX = ${LAT_MIN}, ${LAT_MAX}
TARGET_DLON = ${RESOLUTION}
TARGET_DLAT = ${RESOLUTION}

# Buffer for subsetting (degrees)
BUFFER = 1.0

print("Loading HRRR coordinates...")
hrrr = Dataset(HRRR_FILE, 'r')
hrrr_lon2d_full = hrrr.variables['longitude'][:]
hrrr_lat2d_full = hrrr.variables['latitude'][:]
hrrr_lon2d_full = np.where(hrrr_lon2d_full > 180, hrrr_lon2d_full - 360, hrrr_lon2d_full)
hrrr_time = np.array(hrrr.variables['time'][:])
n_times = len(hrrr_time)
print(f"  HRRR full grid: {hrrr_lon2d_full.shape}, {n_times} times")

# Subset HRRR to target domain + buffer (memory optimization)
print("Subsetting HRRR to target domain...")
hrrr_mask = ((hrrr_lon2d_full >= TARGET_LON_MIN - BUFFER) &
             (hrrr_lon2d_full <= TARGET_LON_MAX + BUFFER) &
             (hrrr_lat2d_full >= TARGET_LAT_MIN - BUFFER) &
             (hrrr_lat2d_full <= TARGET_LAT_MAX + BUFFER))

# Find bounding box indices for HRRR subset
rows_with_data = np.any(hrrr_mask, axis=1)
cols_with_data = np.any(hrrr_mask, axis=0)
if np.any(rows_with_data) and np.any(cols_with_data):
    row_min, row_max = np.where(rows_with_data)[0][[0, -1]]
    col_min, col_max = np.where(cols_with_data)[0][[0, -1]]
    hrrr_row_slice = slice(row_min, row_max + 1)
    hrrr_col_slice = slice(col_min, col_max + 1)
    hrrr_lon2d = np.array(hrrr_lon2d_full[hrrr_row_slice, hrrr_col_slice], dtype=np.float32)
    hrrr_lat2d = np.array(hrrr_lat2d_full[hrrr_row_slice, hrrr_col_slice], dtype=np.float32)
    print(f"  HRRR subset: {hrrr_lon2d.shape} (reduced from {hrrr_lon2d_full.shape})")
else:
    print("  WARNING: No HRRR data in target domain, using GFS only")
    hrrr_lon2d = np.array([[TARGET_LON_MIN]])
    hrrr_lat2d = np.array([[0.0]])  # Outside domain
    hrrr_row_slice = slice(0, 1)
    hrrr_col_slice = slice(0, 1)

# Free full arrays
del hrrr_lon2d_full, hrrr_lat2d_full, hrrr_mask
gc.collect()

print("Loading GFS...")
gfs = Dataset(GFS_FILE, 'r')
gfs_lat_full = np.array(gfs.variables['latitude'][:], dtype=np.float32)
gfs_lon_full = np.array(gfs.variables['longitude'][:], dtype=np.float32)
gfs_time = np.array(gfs.variables['time'][:])
gfs_lon_180 = np.where(gfs_lon_full > 180, gfs_lon_full - 360, gfs_lon_full)

# Subset GFS to domain
lat_mask = (gfs_lat_full >= TARGET_LAT_MIN - 1) & (gfs_lat_full <= TARGET_LAT_MAX + 1)
lon_mask = (gfs_lon_180 >= TARGET_LON_MIN - 1) & (gfs_lon_180 <= TARGET_LON_MAX + 1)
gfs_lat_idx = np.where(lat_mask)[0]
gfs_lon_idx = np.where(lon_mask)[0]
gfs_lat = gfs_lat_full[lat_mask]
gfs_lon = gfs_lon_180[lon_mask]
print(f"  GFS subset: {len(gfs_lat)} x {len(gfs_lon)}")

print("Creating target grid...")
target_lon = np.arange(TARGET_LON_MIN, TARGET_LON_MAX + TARGET_DLON/2, TARGET_DLON, dtype=np.float32)
target_lat = np.arange(TARGET_LAT_MIN, TARGET_LAT_MAX + TARGET_DLAT/2, TARGET_DLAT, dtype=np.float32)
target_lon2d, target_lat2d = np.meshgrid(target_lon, target_lat)
ny, nx = len(target_lat), len(target_lon)
print(f"  Grid: {ny} x {nx} = {ny*nx:,} points")

print("Building HRRR spatial index (subset only)...")
hrrr_points = np.column_stack([hrrr_lon2d.ravel(), hrrr_lat2d.ravel()])
hrrr_tree = cKDTree(hrrr_points)
target_points_flat = np.column_stack([target_lon2d.ravel(), target_lat2d.ravel()])
distances, hrrr_indices = hrrr_tree.query(target_points_flat)
hrrr_indices = hrrr_indices.reshape(ny, nx)
distances = distances.reshape(ny, nx)

# HRRR valid mask: use HRRR where distance < 0.1 deg and within lat range
hrrr_lat_min = float(hrrr_lat2d.min())
hrrr_lat_max = float(hrrr_lat2d.max())
hrrr_valid_mask = (distances < 0.1) & (target_lat2d >= hrrr_lat_min) & (target_lat2d <= hrrr_lat_max)
print(f"  HRRR coverage: {100*np.sum(hrrr_valid_mask)/hrrr_valid_mask.size:.1f}%")

# Free memory
del hrrr_points, target_points_flat, distances
gc.collect()

print("Setting up GFS temporal interpolation...")
gfs_time_interp = interp1d(gfs_time, np.arange(len(gfs_time)),
                            kind='linear', bounds_error=False, fill_value='extrapolate')
target_to_gfs_idx = gfs_time_interp(hrrr_time)

print("Creating output NetCDF...")
ncout = Dataset(OUTPUT_FILE, 'w', format='NETCDF4')
ncout.createDimension('time', None)
ncout.createDimension('y', ny)
ncout.createDimension('x', nx)

time_var = ncout.createVariable('time', 'f8', ('time',))
time_var.units = 'seconds since 1970-01-01 00:00:00.0 0:00'
time_var.long_name = 'verification time generated by wgrib2 function verftime()'
time_var.reference_time = float(hrrr_time[0])
time_var.reference_time_type = 3
time_var.reference_date = datetime.utcfromtimestamp(float(hrrr_time[0])).strftime('%Y.%m.%d %H:%M:%S UTC')
time_var.reference_time_description = 'forecast or accumulated, reference date is fixed'
time_var.time_step_setting = 'auto'
time_var.time_step = 0.
time_var.axis = 'T'
time_var[:] = hrrr_time

lat_var = ncout.createVariable('latitude', 'f8', ('y', 'x'))
lat_var.units = 'degrees_north'
lat_var.long_name = 'latitude'
lat_var.axis = 'Y'
lat_var.standard_name = 'latitude'
lat_var[:] = target_lat2d

lon_var = ncout.createVariable('longitude', 'f8', ('y', 'x'))
lon_var.units = 'degrees_east'
lon_var.long_name = 'longitude'
lon_var.axis = 'X'
lon_var.standard_name = 'longitude'
lon_var[:] = target_lon2d

source_var = ncout.createVariable('data_source', 'i1', ('y', 'x'))
source_var.long_name = 'Data source (1=HRRR, 0=GFS)'
source_var[:] = hrrr_valid_mask.astype(np.int8)

ncout.title = 'Blended HRRR+GFS Forcing for CDEPS/DATM'
ncout.source = 'HRRR (CONUS) + GFS (gap fill)'
ncout.history = f'Created {datetime.now().strftime("%Y-%m-%d %H:%M UTC")}'
ncout.Conventions = 'CF-1.6'

# Variable mapping (HRRR name -> GFS name)
VARIABLES = [
    ('UGRD_10maboveground', 'UGRD_10maboveground'),
    ('VGRD_10maboveground', 'VGRD_10maboveground'),
    ('TMP_2maboveground', 'TMP_2maboveground'),
    ('SPFH_2maboveground', 'SPFH_2maboveground'),
    ('PRATE_surface', 'PRATE_surface'),
    ('DSWRF_surface', 'DSWRF_surface'),
    ('DLWRF_surface', 'DLWRF_surface'),
    ('MSLMA_meansealevel', 'PRMSL_meansealevel'),
]

# GFS lat order
if gfs_lat[0] > gfs_lat[-1]:
    gfs_lat_asc = gfs_lat[::-1]
    gfs_flip = True
else:
    gfs_lat_asc = gfs_lat
    gfs_flip = False

print("Processing variables...")
for hrrr_name, gfs_name in VARIABLES:
    if hrrr_name not in hrrr.variables or gfs_name not in gfs.variables:
        print(f"  Skipping {hrrr_name}")
        continue

    print(f"  {hrrr_name}...", end='', flush=True)

    hrrr_var = hrrr.variables[hrrr_name]
    gfs_var = gfs.variables[gfs_name]

    out_var = ncout.createVariable(hrrr_name, 'f4', ('time', 'y', 'x'), fill_value=9.999e+20)
    out_var.short_name = hrrr_name
    out_var.units = hrrr_var.units if hasattr(hrrr_var, 'units') else ''
    out_var.long_name = hrrr_var.long_name if hasattr(hrrr_var, 'long_name') else hrrr_name

    for t in range(n_times):
        # HRRR data - read only the subset
        hrrr_data = np.array(hrrr_var[t, hrrr_row_slice, hrrr_col_slice], dtype=np.float32).ravel()
        hrrr_data = np.where(hrrr_data > 1e10, np.nan, hrrr_data)
        hrrr_regrid = hrrr_data[hrrr_indices]

        # GFS data with temporal interpolation
        gfs_t_idx = target_to_gfs_idx[t]
        t_low = int(np.floor(gfs_t_idx))
        t_high = int(np.ceil(gfs_t_idx))
        t_frac = gfs_t_idx - t_low
        t_low = max(0, min(t_low, len(gfs_time) - 1))
        t_high = max(0, min(t_high, len(gfs_time) - 1))

        gfs_data_low = np.array(gfs_var[t_low, gfs_lat_idx[0]:gfs_lat_idx[-1]+1, gfs_lon_idx[0]:gfs_lon_idx[-1]+1], dtype=np.float32)
        gfs_data_high = np.array(gfs_var[t_high, gfs_lat_idx[0]:gfs_lat_idx[-1]+1, gfs_lon_idx[0]:gfs_lon_idx[-1]+1], dtype=np.float32)

        if t_low == t_high:
            gfs_data = gfs_data_low
        else:
            gfs_data = (1 - t_frac) * gfs_data_low + t_frac * gfs_data_high

        if gfs_flip:
            gfs_data = gfs_data[::-1, :]

        gfs_interp = RegularGridInterpolator(
            (gfs_lat_asc, gfs_lon), gfs_data,
            method='linear', bounds_error=False, fill_value=np.nan
        )
        gfs_regrid = gfs_interp(np.column_stack([target_lat2d.ravel(),
                                                  target_lon2d.ravel()])).reshape(ny, nx)

        # Combine: HRRR where valid, GFS elsewhere
        combined = np.where(hrrr_valid_mask & ~np.isnan(hrrr_regrid), hrrr_regrid, gfs_regrid)
        out_var[t, :, :] = combined

        # Free memory each timestep
        del hrrr_data, hrrr_regrid, gfs_data_low, gfs_data_high, gfs_data, gfs_regrid, combined

    gc.collect()
    print(" done")

ncout.close()
hrrr.close()
gfs.close()

print(f"\nOutput: {OUTPUT_FILE}")
print("SUCCESS!")
PYEOF

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
USHnos=${USHnos:-$(dirname $0)}
SCRIP_SCRIPT="${USHnos}/pysh/proc_scrip.py"

if [ ! -s "$SCRIP_SCRIPT" ]; then
    # Try alternate location
    SCRIP_SCRIPT="$(dirname $0)/pysh/proc_scrip.py"
fi

if [ -s "$SCRIP_SCRIPT" ]; then
    python3 $SCRIP_SCRIPT --ifile $OUTPUT_FILE --ofile $(basename $SCRIP_FILE) --odir $OUTPUT_DIR
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
    echo "  python3 proc_scrip.py --ifile $OUTPUT_FILE --ofile ${BASENAME}_scrip.nc"
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
