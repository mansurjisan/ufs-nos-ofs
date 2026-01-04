# WCOSS2 UFS-Coastal Testing Guide

Testing UFS file generation within the SECOFS operational workflow on WCOSS2.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Configuration Steps](#configuration-steps)
4. [Running the Test](#running-the-test)
5. [Verifying Output](#verifying-output)
6. [Troubleshooting](#troubleshooting)

---

## Overview

This guide covers testing the UFS-Coastal file generation integrated into the nosofs workflow. The goal is to verify that the following files are generated during the prep stage:

| File Type | Files Generated |
|-----------|-----------------|
| ESMF Mesh | `gfs_esmf_mesh.nc`, `hrrr_esmf_mesh.nc` |
| Data Files | `gfs_for_esmf.nc`, `hrrr_for_esmf.nc` |
| UFS Config | `model_configure`, `datm_in`, `datm.streams`, `ufs.configure` |

---

## Prerequisites

### Required Modules

```bash
module load wgrib2
module load esmf
module load python/3.8.6
```

### Python Dependencies

```bash
python3 -c "import xarray; import netCDF4; import numpy; print('Python deps OK')"
```

If missing:
```bash
pip install --user xarray netCDF4
```

### Verify Tools

```bash
which wgrib2              # Should return path
which ESMF_Scrip2Unstruct # Should return path
```

---

## Configuration Steps

### Step 1: Update secofs.ctl

Edit the control file to enable ESMF mesh generation:

```bash
# Path on WCOSS2 (adjust for dev/prod)
vi /lfs/h1/ops/dev/nosofs.v3.7.0/fix/secofs/secofs.ctl
```

Add or modify this line (after `DBASE_MET_FOR2=HRRR`):

```bash
# ESMF mesh generation for UFS-Coastal DATM (set to true to enable)
export GENERATE_ESMF_MESH=true
```

### Step 2: Verify Template Files

Ensure all UFS templates are in place:

```bash
FIXofs=/lfs/h1/ops/dev/nosofs.v3.7.0/fix/secofs

ls -la ${FIXofs}/ufs.configure
ls -la ${FIXofs}/model_configure.template
ls -la ${FIXofs}/datm_in.template
ls -la ${FIXofs}/datm.streams.template
```

**Expected output:**
```
-rwxrwxrwx 1 ... 2821 ... ufs.configure
-rwxrwxrwx 1 ... 2190 ... model_configure.template
-rwxrwxrwx 1 ... 2156 ... datm_in.template
-rwxrwxrwx 1 ... 4146 ... datm.streams.template
```

### Step 3: Verify Scripts

```bash
USHnos=/lfs/h1/ops/dev/nosofs.v3.7.0/ush

ls -la ${USHnos}/nos_ofs_create_esmf_mesh.sh
ls -la ${USHnos}/nos_ofs_gen_ufs_config.sh
ls -la ${USHnos}/pysh/proc_scrip.py
ls -la ${USHnos}/pysh/modify_gfs_4_esmfmesh.py
ls -la ${USHnos}/pysh/modify_hrrr_4_esmfmesh.py
```

---

## Running the Test

### Option A: Submit Prep Job (Recommended)

```bash
# Set date/cycle
export PDY=20260103
export cyc=06

# Submit prep job
qsub /lfs/h1/ops/dev/nosofs.v3.7.0/ecf/jnos_secofs_prep.ecf
```

### Option B: Run Interactively (For Debugging)

```bash
# Set environment
export PDY=20260103
export cyc=06
export RUN=secofs
export NET=nos
export model=nosofs
export HOMEnos=/lfs/h1/ops/dev/nosofs.v3.7.0
export FIXofs=${HOMEnos}/fix/secofs
export USHnos=${HOMEnos}/ush
export EXECnos=${HOMEnos}/exec
export DATA=/lfs/h2/emc/ptmp/${USER}/secofs.${PDY}
export COMOUT=/lfs/h2/emc/ptmp/${USER}/com/nos/${PDY}

# Source control file
. ${FIXofs}/secofs.ctl

# Run prep script
${HOMEnos}/scripts/exnos_ofs_prep.sh 2>&1 | tee prep_${PDY}_${cyc}.log
```

### Option C: Test ESMF Mesh Script Standalone

```bash
# Set environment
export USHnos=/lfs/h1/ops/dev/nosofs.v3.7.0/ush
export WGRIB2=$(which wgrib2)
export ESMF_SCRIP2UNSTRUCT=$(which ESMF_Scrip2Unstruct)

# Find a GFS file
GFS_FILE=$(ls /lfs/h1/ops/prod/com/gfs/v16.3/gfs.${PDY}/${cyc}/atmos/gfs.t${cyc}z.pgrb2.0p25.f000)

# Test GFS mesh generation
mkdir -p /lfs/h2/emc/ptmp/${USER}/esmf_test
${USHnos}/nos_ofs_create_esmf_mesh.sh GFS25 ${GFS_FILE} /lfs/h2/emc/ptmp/${USER}/esmf_test
```

---

## Verifying Output

### Quick Verification Script

Create and run this script:

```bash
#!/bin/bash
# verify_ufs_files.sh
# Usage: ./verify_ufs_files.sh /path/to/DATA

DATA=${1:-$DATA}

echo "============================================"
echo "UFS File Generation Verification"
echo "DATA: $DATA"
echo "============================================"

check_file() {
    if [ -s "$1" ]; then
        SIZE=$(ls -lh "$1" 2>/dev/null | awk '{print $5}')
        echo "[OK]   $1 ($SIZE)"
        return 0
    else
        echo "[FAIL] $1 - NOT FOUND"
        return 1
    fi
}

PASS=0
FAIL=0

echo ""
echo "--- ESMF Mesh Files ---"
check_file "${DATA}/esmf_mesh/gfs_esmf_mesh.nc" && ((PASS++)) || ((FAIL++))
check_file "${DATA}/esmf_mesh/hrrr_esmf_mesh.nc" && ((PASS++)) || ((FAIL++))

echo ""
echo "--- Intermediate Files ---"
check_file "${DATA}/esmf_mesh/gfs_for_esmf.nc" && ((PASS++)) || ((FAIL++))
check_file "${DATA}/esmf_mesh/hrrr_for_esmf.nc" && ((PASS++)) || ((FAIL++))
check_file "${DATA}/esmf_mesh/gfs_scrip.nc" && ((PASS++)) || ((FAIL++))
check_file "${DATA}/esmf_mesh/hrrr_scrip.nc" && ((PASS++)) || ((FAIL++))

echo ""
echo "--- UFS Config Files ---"
check_file "${DATA}/model_configure" && ((PASS++)) || ((FAIL++))
check_file "${DATA}/datm_in" && ((PASS++)) || ((FAIL++))
check_file "${DATA}/datm.streams" && ((PASS++)) || ((FAIL++))
check_file "${DATA}/ufs.configure" && ((PASS++)) || ((FAIL++))

echo ""
echo "--- INPUT Directory ---"
check_file "${DATA}/INPUT/gfs_esmf_mesh.nc" && ((PASS++)) || ((FAIL++))
check_file "${DATA}/INPUT/gfs_for_esmf.nc" && ((PASS++)) || ((FAIL++))

echo ""
echo "============================================"
echo "Summary: $PASS passed, $FAIL failed"
echo "============================================"

if [ $FAIL -gt 0 ]; then
    exit 1
fi
```

### Manual Verification Commands

```bash
# Check ESMF mesh structure
ncdump -h ${DATA}/esmf_mesh/gfs_esmf_mesh.nc | head -40

# Verify mesh dimensions
ncdump -h ${DATA}/esmf_mesh/gfs_esmf_mesh.nc | grep -E "nodeCount|elementCount"

# Check config file substitutions worked
echo "--- model_configure ---"
grep -E "start_year|start_month|start_day|start_hour|nhours_fcst" ${DATA}/model_configure

echo "--- datm.streams ---"
grep -E "yearFirst|yearLast|stream_data_files" ${DATA}/datm.streams | head -10

echo "--- datm_in ---"
grep -E "nx_global|ny_global|model_meshfile" ${DATA}/datm_in
```

### Check COMOUT Copies

```bash
ls -la ${COMOUT}/nos.secofs.t${cyc}z.*esmf_mesh*
ls -la ${COMOUT}/nos.secofs.t${cyc}z.*model_configure*
ls -la ${COMOUT}/nos.secofs.t${cyc}z.*datm*
```

---

## Troubleshooting

### Issue: ESMF mesh files not created

**Check log files:**
```bash
cat ${DATA}/esmf_mesh/gfs_esmf_mesh.log
cat ${DATA}/esmf_mesh/hrrr_esmf_mesh.log
```

**Common causes:**
1. `GENERATE_ESMF_MESH` not set to `true` in secofs.ctl
2. wgrib2 or ESMF_Scrip2Unstruct not in PATH
3. Python dependencies missing (xarray, netCDF4)
4. GFS/HRRR GRIB2 files not found

### Issue: wgrib2 not creating NetCDF

**Check wgrib2 version:**
```bash
wgrib2 -version
```

**Test wgrib2 manually:**
```bash
GFS_FILE=/lfs/h1/ops/prod/com/gfs/v16.3/gfs.${PDY}/${cyc}/atmos/gfs.t${cyc}z.pgrb2.0p25.f000

wgrib2 ${GFS_FILE} \
    -match ":(UGRD|VGRD):10 m above ground:|:(TMP|SPFH):2 m above ground:|:PRMSL:mean sea level:|:(DSWRF|DLWRF|PRATE):surface:" \
    -netcdf test_gfs.nc

ls -la test_gfs.nc
ncdump -h test_gfs.nc
```

### Issue: Python script errors

**Check Python environment:**
```bash
python3 --version
python3 -c "import sys; print(sys.path)"
python3 -c "import xarray; print(xarray.__version__)"
python3 -c "import netCDF4; print(netCDF4.__version__)"
```

**Test proc_scrip.py manually:**
```bash
python3 ${USHnos}/pysh/proc_scrip.py --help
python3 ${USHnos}/pysh/proc_scrip.py \
    --ifile ${DATA}/esmf_mesh/gfs_for_esmf.nc \
    --ofile test_scrip.nc \
    --odir ./
```

### Issue: UFS config files have wrong values

**Check environment variables:**
```bash
echo "PDY=$PDY"
echo "cyc=$cyc"
echo "DATA=$DATA"
echo "FIXofs=$FIXofs"
```

**Test config generation manually:**
```bash
export PDY=20260103
export cyc=06
export DATA=/lfs/h2/emc/ptmp/${USER}/test_config
export FIXofs=/lfs/h1/ops/dev/nosofs.v3.7.0/fix/secofs

mkdir -p $DATA
${USHnos}/nos_ofs_gen_ufs_config.sh -v
```

### Issue: HRRR mesh not created but GFS is

**Check if HRRR sflux files exist:**
```bash
ls -la ${DATA}/sflux/sflux_air_2.*.nc
```

If no HRRR sflux files, HRRR mesh generation is skipped (expected behavior).

---

## Expected File Sizes

| File | Approximate Size |
|------|-----------------|
| `gfs_esmf_mesh.nc` | 500 KB - 2 MB |
| `hrrr_esmf_mesh.nc` | 20 - 30 MB |
| `gfs_for_esmf.nc` | 5 - 20 MB |
| `hrrr_for_esmf.nc` | 100 - 500 MB |
| `model_configure` | ~2 KB |
| `datm_in` | ~2 KB |
| `datm.streams` | ~4 KB |
| `ufs.configure` | ~3 KB |

---

## Next Steps After Successful Test

Once UFS files are generated successfully:

1. **Copy param.nml.ufs** for actual UFS-Coastal run:
   ```bash
   cp ${FIXofs}/secofs.param.nml.ufs ${DATA}/param.nml
   ```

2. **Stage files for UFS-Coastal**:
   ```bash
   mkdir -p ${DATA}/INPUT
   cp ${DATA}/esmf_mesh/*_esmf_mesh.nc ${DATA}/INPUT/
   cp ${DATA}/esmf_mesh/*_for_esmf.nc ${DATA}/INPUT/
   ```

3. **Run UFS-Coastal** with the generated configuration files

---

## Document History

| Date | Author | Description |
|------|--------|-------------|
| 2026-01-03 | Claude Code | Initial WCOSS2 testing guide |

---

*Part of SECOFS UFS-Coastal Transition Project*
