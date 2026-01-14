#!/usr/bin/env python3
"""
Standalone debug script for HRRR+GFS blending.
Run interactively on WCOSS2 to identify memory issues.

Usage:
    python3 debug_blend.py HRRR_FILE GFS_FILE OUTPUT_FILE DOMAIN

Example:
    python3 debug_blend.py hrrr_forcing.nc gfs_forcing.nc secofs_forcing.nc SECOFS
"""

import sys
import os

print("Python version:", sys.version)
print("Python executable:", sys.executable)

# Check memory before imports
try:
    import resource
    mem_before = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024
    print(f"Memory before imports: {mem_before:.1f} MB")
except:
    print("Cannot check memory usage")

print("\nStep 1: Importing numpy...")
import numpy as np
print(f"  numpy version: {np.__version__}")

print("Step 2: Importing netCDF4...")
from netCDF4 import Dataset
print("  netCDF4 imported OK")

print("Step 3: Importing scipy.spatial.cKDTree...")
from scipy.spatial import cKDTree
print("  cKDTree imported OK")

print("Step 4: Importing scipy.interpolate...")
from scipy.interpolate import RegularGridInterpolator, interp1d
print("  interpolate imported OK")

print("Step 5: Importing other modules...")
from datetime import datetime
import gc
print("  All imports OK")

try:
    mem_after = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024
    print(f"Memory after imports: {mem_after:.1f} MB")
except:
    pass

# Parse arguments
if len(sys.argv) < 5:
    print("\nUsage: python3 debug_blend.py HRRR_FILE GFS_FILE OUTPUT_FILE DOMAIN")
    print("Example: python3 debug_blend.py hrrr_forcing.nc gfs_forcing.nc secofs_forcing.nc SECOFS")
    sys.exit(1)

HRRR_FILE = sys.argv[1]
GFS_FILE = sys.argv[2]
OUTPUT_FILE = sys.argv[3]
DOMAIN = sys.argv[4]

# Domain bounds
DOMAINS = {
    'ATLANTIC': (-98.0, -55.0, 10.0, 53.0),
    'SECOFS': (-82.0, -73.0, 23.0, 37.0),
    'STOFS3D_ATL': (-99.0, -52.0, 7.0, 53.0),
}

if DOMAIN not in DOMAINS:
    print(f"ERROR: Unknown domain {DOMAIN}")
    sys.exit(1)

TARGET_LON_MIN, TARGET_LON_MAX, TARGET_LAT_MIN, TARGET_LAT_MAX = DOMAINS[DOMAIN]
TARGET_DLON = 0.025
TARGET_DLAT = 0.025
BUFFER = 1.0

print(f"\n{'='*50}")
print(f"Configuration:")
print(f"  HRRR: {HRRR_FILE}")
print(f"  GFS:  {GFS_FILE}")
print(f"  OUT:  {OUTPUT_FILE}")
print(f"  Domain: {DOMAIN}")
print(f"  Bounds: {TARGET_LAT_MIN}°N-{TARGET_LAT_MAX}°N, {TARGET_LON_MIN}°E-{TARGET_LON_MAX}°E")
print(f"  Resolution: {TARGET_DLON}°")
print(f"{'='*50}\n")

# Check files exist
if not os.path.exists(HRRR_FILE):
    print(f"ERROR: HRRR file not found: {HRRR_FILE}")
    sys.exit(1)
if not os.path.exists(GFS_FILE):
    print(f"ERROR: GFS file not found: {GFS_FILE}")
    sys.exit(1)

print("Step 6: Opening HRRR file...")
hrrr = Dataset(HRRR_FILE, 'r')
print(f"  HRRR file opened OK")
print(f"  Dimensions: {dict(hrrr.dimensions)}")
print(f"  Variables: {list(hrrr.variables.keys())[:10]}...")

print("\nStep 7: Reading HRRR coordinates (as masked array, not loading fully)...")
hrrr_lon2d_full = hrrr.variables['longitude'][:]
hrrr_lat2d_full = hrrr.variables['latitude'][:]
print(f"  HRRR lon shape: {hrrr_lon2d_full.shape}")
print(f"  HRRR lat shape: {hrrr_lat2d_full.shape}")

# Convert to -180 to 180
hrrr_lon2d_full = np.where(hrrr_lon2d_full > 180, hrrr_lon2d_full - 360, hrrr_lon2d_full)

hrrr_time = np.array(hrrr.variables['time'][:])
n_times = len(hrrr_time)
print(f"  HRRR times: {n_times}")

try:
    mem_now = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024
    print(f"  Memory now: {mem_now:.1f} MB")
except:
    pass

print("\nStep 8: Subsetting HRRR to target domain...")
hrrr_mask = ((hrrr_lon2d_full >= TARGET_LON_MIN - BUFFER) &
             (hrrr_lon2d_full <= TARGET_LON_MAX + BUFFER) &
             (hrrr_lat2d_full >= TARGET_LAT_MIN - BUFFER) &
             (hrrr_lat2d_full <= TARGET_LAT_MAX + BUFFER))

rows_with_data = np.any(hrrr_mask, axis=1)
cols_with_data = np.any(hrrr_mask, axis=0)

if np.any(rows_with_data) and np.any(cols_with_data):
    row_min, row_max = np.where(rows_with_data)[0][[0, -1]]
    col_min, col_max = np.where(cols_with_data)[0][[0, -1]]
    hrrr_row_slice = slice(row_min, row_max + 1)
    hrrr_col_slice = slice(col_min, col_max + 1)
    print(f"  HRRR subset rows: {row_min} to {row_max} ({row_max-row_min+1} rows)")
    print(f"  HRRR subset cols: {col_min} to {col_max} ({col_max-col_min+1} cols)")

    hrrr_lon2d = np.array(hrrr_lon2d_full[hrrr_row_slice, hrrr_col_slice], dtype=np.float32)
    hrrr_lat2d = np.array(hrrr_lat2d_full[hrrr_row_slice, hrrr_col_slice], dtype=np.float32)
    print(f"  HRRR subset shape: {hrrr_lon2d.shape}")
else:
    print("  WARNING: No HRRR data in target domain!")
    hrrr_lon2d = np.array([[TARGET_LON_MIN]], dtype=np.float32)
    hrrr_lat2d = np.array([[0.0]], dtype=np.float32)
    hrrr_row_slice = slice(0, 1)
    hrrr_col_slice = slice(0, 1)

# Free memory
del hrrr_lon2d_full, hrrr_lat2d_full, hrrr_mask
gc.collect()

try:
    mem_now = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024
    print(f"  Memory after HRRR subset: {mem_now:.1f} MB")
except:
    pass

print("\nStep 9: Opening GFS file...")
gfs = Dataset(GFS_FILE, 'r')
print(f"  GFS file opened OK")
print(f"  Dimensions: {dict(gfs.dimensions)}")

print("\nStep 10: Reading GFS coordinates...")
gfs_lat_full = np.array(gfs.variables['latitude'][:], dtype=np.float32)
gfs_lon_full = np.array(gfs.variables['longitude'][:], dtype=np.float32)
gfs_time = np.array(gfs.variables['time'][:])
print(f"  GFS lat shape: {gfs_lat_full.shape}")
print(f"  GFS lon shape: {gfs_lon_full.shape}")
print(f"  GFS times: {len(gfs_time)}")

gfs_lon_180 = np.where(gfs_lon_full > 180, gfs_lon_full - 360, gfs_lon_full)

# Subset GFS
lat_mask = (gfs_lat_full >= TARGET_LAT_MIN - 1) & (gfs_lat_full <= TARGET_LAT_MAX + 1)
lon_mask = (gfs_lon_180 >= TARGET_LON_MIN - 1) & (gfs_lon_180 <= TARGET_LON_MAX + 1)
gfs_lat_idx = np.where(lat_mask)[0]
gfs_lon_idx = np.where(lon_mask)[0]
gfs_lat = gfs_lat_full[lat_mask]
gfs_lon = gfs_lon_180[lon_mask]
print(f"  GFS subset: {len(gfs_lat)} x {len(gfs_lon)}")

print("\nStep 11: Creating target grid...")
target_lon = np.arange(TARGET_LON_MIN, TARGET_LON_MAX + TARGET_DLON/2, TARGET_DLON, dtype=np.float32)
target_lat = np.arange(TARGET_LAT_MIN, TARGET_LAT_MAX + TARGET_DLAT/2, TARGET_DLAT, dtype=np.float32)
target_lon2d, target_lat2d = np.meshgrid(target_lon, target_lat)
ny, nx = len(target_lat), len(target_lon)
print(f"  Target grid: {ny} x {nx} = {ny*nx:,} points")

try:
    mem_now = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024
    print(f"  Memory now: {mem_now:.1f} MB")
except:
    pass

print("\nStep 12: Building KD-tree for HRRR subset...")
hrrr_points = np.column_stack([hrrr_lon2d.ravel(), hrrr_lat2d.ravel()])
print(f"  HRRR points for KD-tree: {len(hrrr_points):,}")
hrrr_tree = cKDTree(hrrr_points)
print("  KD-tree built OK")

print("\nStep 13: Querying KD-tree...")
target_points_flat = np.column_stack([target_lon2d.ravel(), target_lat2d.ravel()])
distances, hrrr_indices = hrrr_tree.query(target_points_flat)
hrrr_indices = hrrr_indices.reshape(ny, nx)
distances = distances.reshape(ny, nx)
print("  KD-tree query OK")

# HRRR valid mask
hrrr_lat_min = float(hrrr_lat2d.min())
hrrr_lat_max = float(hrrr_lat2d.max())
hrrr_valid_mask = (distances < 0.1) & (target_lat2d >= hrrr_lat_min) & (target_lat2d <= hrrr_lat_max)
print(f"  HRRR coverage: {100*np.sum(hrrr_valid_mask)/hrrr_valid_mask.size:.1f}%")

# Free memory
del hrrr_points, target_points_flat, distances
gc.collect()

try:
    mem_now = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024
    print(f"  Memory now: {mem_now:.1f} MB")
except:
    pass

print("\nStep 14: Setting up temporal interpolation...")
gfs_time_interp = interp1d(gfs_time, np.arange(len(gfs_time)),
                            kind='linear', bounds_error=False, fill_value='extrapolate')
target_to_gfs_idx = gfs_time_interp(hrrr_time)
print("  Temporal interpolation setup OK")

print("\nStep 15: Creating output NetCDF...")
ncout = Dataset(OUTPUT_FILE, 'w', format='NETCDF4')
ncout.createDimension('time', None)
ncout.createDimension('y', ny)
ncout.createDimension('x', nx)

time_var = ncout.createVariable('time', 'f8', ('time',))
time_var.units = 'seconds since 1970-01-01 00:00:00'
time_var.calendar = 'standard'
time_var[:] = hrrr_time

lat_var = ncout.createVariable('latitude', 'f4', ('y', 'x'))
lat_var.units = 'degrees_north'
lat_var[:] = target_lat2d

lon_var = ncout.createVariable('longitude', 'f4', ('y', 'x'))
lon_var.units = 'degrees_east'
lon_var[:] = target_lon2d

ncout.Conventions = 'CF-1.6'
ncout.title = 'Blended HRRR+GFS Forcing'
print("  Output file created OK")

# GFS lat order
if gfs_lat[0] > gfs_lat[-1]:
    gfs_lat_asc = gfs_lat[::-1]
    gfs_flip = True
else:
    gfs_lat_asc = gfs_lat
    gfs_flip = False

# Variable mapping
VARIABLES = [
    ('UGRD_10maboveground', 'UGRD_10maboveground'),
    ('VGRD_10maboveground', 'VGRD_10maboveground'),
]

print("\nStep 16: Processing variables (just wind for testing)...")
for hrrr_name, gfs_name in VARIABLES:
    if hrrr_name not in hrrr.variables:
        print(f"  Skipping {hrrr_name} - not in HRRR")
        continue
    if gfs_name not in gfs.variables:
        print(f"  Skipping {gfs_name} - not in GFS")
        continue

    print(f"  Processing {hrrr_name}...")

    hrrr_var = hrrr.variables[hrrr_name]
    gfs_var = gfs.variables[gfs_name]

    out_var = ncout.createVariable(hrrr_name, 'f4', ('time', 'y', 'x'), fill_value=9.999e+20)

    # Just process first 2 timesteps for testing
    for t in range(min(2, n_times)):
        print(f"    Time step {t}...")

        # HRRR data
        hrrr_data = np.array(hrrr_var[t, hrrr_row_slice, hrrr_col_slice], dtype=np.float32).ravel()
        hrrr_data = np.where(hrrr_data > 1e10, np.nan, hrrr_data)
        hrrr_regrid = hrrr_data[hrrr_indices]

        # GFS data
        gfs_t_idx = target_to_gfs_idx[t]
        t_low = int(np.floor(gfs_t_idx))
        t_high = int(np.ceil(gfs_t_idx))
        t_frac = gfs_t_idx - t_low
        t_low = max(0, min(t_low, len(gfs_time) - 1))
        t_high = max(0, min(t_high, len(gfs_time) - 1))

        gfs_data_low = np.array(gfs_var[t_low, gfs_lat_idx[0]:gfs_lat_idx[-1]+1, gfs_lon_idx[0]:gfs_lon_idx[-1]+1], dtype=np.float32)

        if t_low == t_high:
            gfs_data = gfs_data_low
        else:
            gfs_data_high = np.array(gfs_var[t_high, gfs_lat_idx[0]:gfs_lat_idx[-1]+1, gfs_lon_idx[0]:gfs_lon_idx[-1]+1], dtype=np.float32)
            gfs_data = (1 - t_frac) * gfs_data_low + t_frac * gfs_data_high

        if gfs_flip:
            gfs_data = gfs_data[::-1, :]

        gfs_interp = RegularGridInterpolator(
            (gfs_lat_asc, gfs_lon), gfs_data,
            method='linear', bounds_error=False, fill_value=np.nan
        )
        gfs_regrid = gfs_interp(np.column_stack([target_lat2d.ravel(),
                                                  target_lon2d.ravel()])).reshape(ny, nx)

        combined = np.where(hrrr_valid_mask & ~np.isnan(hrrr_regrid), hrrr_regrid, gfs_regrid)
        out_var[t, :, :] = combined

        del hrrr_data, hrrr_regrid, gfs_data, gfs_regrid, combined
        gc.collect()

    print(f"    {hrrr_name} done!")

ncout.close()
hrrr.close()
gfs.close()

print(f"\n{'='*50}")
print("SUCCESS! Debug script completed.")
print(f"Output: {OUTPUT_FILE}")
print(f"{'='*50}")
