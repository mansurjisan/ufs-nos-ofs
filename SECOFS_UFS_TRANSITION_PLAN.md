# SECOFS Transition to UFS-Coastal Framework

## Executive Summary

This plan outlines the transition of SECOFS (Southeast Coastal Ocean Forecast System) from the current COMF/nosofs.v3.7.0 framework to the UFS-Coastal framework, specifically using the **DATM+SCHISM** configuration. The transition will be phased, starting with atmospheric forcing generation to match current outputs, then progressing to full UFS integration.

---

## Current State vs Target State

### Current SECOFS (nosofs.v3.7.0)
```
┌─────────────────────────────────────────────────────────────────┐
│ PREP JOB                                                        │
│ ├── nos_ofs_create_forcing_met.sh (GFS + HRRR)                 │
│ │   └── nos_ofs_create_forcing_met_fvcom (Fortran)             │
│ │   └── Output: sflux_air_*.nc, sflux_rad_*.nc, sflux_prc_*.nc │
│ ├── nos_ofs_create_forcing_river.sh                            │
│ ├── nos_ofs_create_forcing_obc.sh                              │
│ └── Generate param.nml                                          │
├─────────────────────────────────────────────────────────────────┤
│ NOWCAST/FORECAST JOB                                            │
│ └── pschism_WCOSS2 (standalone SCHISM executable)              │
└─────────────────────────────────────────────────────────────────┘
```

### Target SECOFS (UFS-Coastal)
```
┌─────────────────────────────────────────────────────────────────┐
│ PREP JOB (mostly unchanged)                                     │
│ ├── [EXISTING] nos_ofs_create_forcing_river.sh                 │
│ ├── [EXISTING] nos_ofs_create_forcing_obc.sh                   │
│ ├── [NEW] Generate ESMF mesh from SCHISM grid                  │
│ ├── [NEW] Prepare DATM streams (GFS + HRRR)                    │
│ └── [NEW] Generate NUOPC run sequence config                   │
├─────────────────────────────────────────────────────────────────┤
│ NOWCAST/FORECAST JOB                                            │
│ └── ufs_coastal.x (DATM + SCHISM coupled via CMEPS)            │
│     ├── DATM: Reads GFS/HRRR NetCDF directly                   │
│     ├── CMEPS: Mediator handles field exchange                 │
│     └── SCHISM: Receives atm forcing via NUOPC                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Environment Setup & Build UFS-Coastal

### 1.1 Clone Required Repositories

```bash
# On WCOSS2
cd /lfs/h1/nos/estofs/noscrub/$USER/packages

# Clone UFS-Coastal App
git clone --recursive https://github.com/oceanmodeling/ufs-coastal-app.git
cd ufs-coastal-app

# Checkout develop branch
git checkout develop
git submodule update --init --recursive
```

### 1.2 Build UFS-Coastal with DATM+SCHISM

```bash
# Load WCOSS2 modules
module purge
module load PrgEnv-intel/8.1.0
module load intel/19.1.3.304
module load cray-mpich/8.1.7
module load cmake/3.20.2
module load netcdf/4.7.4
module load hdf5/1.10.6

# Build with SCHISM + DATM
cd sorc
CMAKE_FLAGS="-DAPP=CSTL -DCOASTAL_SCHISM=ON -DCDEPS_DATM=ON" ./build.sh

# Verify executable
ls -la ../exec/ufs_coastal.x
```

### 1.3 Verify Build Success

- [ ] `ufs_coastal.x` executable created
- [ ] SCHISM component compiled
- [ ] DATM component compiled
- [ ] CMEPS mediator compiled

---

## Phase 2: Prepare SECOFS Domain for UFS-Coastal

### 2.1 Convert SCHISM Grid to ESMF Mesh

The UFS-Coastal framework requires ESMF mesh format for coupling. Convert `secofs.hgrid.gr3` to ESMF mesh:

```python
# Using PySCHISM or ESMF mesh tools
# Script: create_esmf_mesh_secofs.py

from pyschism.mesh import Hgrid
import ESMF

# Read SCHISM grid
hgrid = Hgrid.open('secofs.hgrid.gr3')

# Convert to ESMF mesh
# Option 1: Use ESMF_Scrip2Unstruct utility
# Option 2: Use pyschism mesh conversion

# Output: secofs_esmf_mesh.nc
```

**Key Files to Generate:**
| File | Description |
|------|-------------|
| `secofs_esmf_mesh.nc` | ESMF unstructured mesh for SCHISM domain |
| `secofs_esmf_mesh_mask.nc` | Land/ocean mask for mesh |
| `secofs_scrip.nc` | SCRIP format grid (intermediate) |

### 2.2 Create DATM Input Streams Configuration

DATM uses "streams" to define input data sources. Create stream configuration for GFS and HRRR:

**File: `datm.streams.xml`**
```xml
<?xml version="1.0"?>
<file id="stream" version="2.0">
  <stream_info name="GFS">
    <taxmode>cycle</taxmode>
    <tintalgo>linear</tintalgo>
    <readmode>single</readmode>
    <mapmask>nomask</mapmask>
    <dtlimit>1.5</dtlimit>
    <vectors>u:v</vectors>
    <meshfile>/path/to/gfs_grid.nc</meshfile>
    <datafiles>
      <file>/path/to/gfs.t06z.pgrb2.0p25.f000.nc</file>
    </datafiles>
    <datavars>
      TMP_2maboveground   Sa_tbot
      SPFH_2maboveground  Sa_shum
      PRES_surface        Sa_pslv
      UGRD_10maboveground Sa_u
      VGRD_10maboveground Sa_v
      DSWRF_surface       Faxa_swdn
      DLWRF_surface       Faxa_lwdn
      PRATE_surface       Faxa_rain
    </datavars>
  </stream_info>
</file>
```

### 2.3 Prepare GFS/HRRR Data in CDEPS-Compatible Format

Current SECOFS uses Fortran to interpolate GFS/HRRR to SCHISM grid. In UFS-Coastal, DATM reads native GFS/HRRR grid and CMEPS handles remapping.

**Option A: Use GFS NetCDF directly (preferred)**
```bash
# Convert GRIB2 to NetCDF with CF conventions
wgrib2 gfs.t06z.pgrb2.0p25.f000 -netcdf gfs.t06z.f000.nc

# Ensure CF-compliant coordinates
ncatted -a coordinates,TMP_2maboveground,o,c,"longitude latitude" gfs.t06z.f000.nc
```

**Option B: Use existing sflux files (interim solution)**
- DATM can read the existing `sflux_air_*.nc` files if properly formatted
- Requires adding ESMF-compatible grid metadata

---

## Phase 3: Configure DATM for SECOFS 06z Cycle

### 3.1 DATM Namelist Configuration

**File: `datm_in`**
```fortran
&datm_nml
  datamode       = 'GFS'
  model_meshfile = '/path/to/secofs_esmf_mesh.nc'
  model_maskfile = '/path/to/secofs_esmf_mesh.nc'
  nx_global      = 1684786    ! SECOFS np_global
  ny_global      = 1          ! unstructured
  restfilm       = 'null'
  factorfn_mesh  = '/path/to/gfs_mesh.nc'
/
```

### 3.2 NUOPC Run Sequence Configuration

**File: `nems.configure`**
```
#############################################
####  NEMS Run-Time Configuration File  #####
#############################################

EARTH_component_list: MED ATM OCN
EARTH_attributes::
  Verbosity = high
::

# ATM = DATM (Data Atmosphere)
ATM_model:                      datm
ATM_petlist_bounds:             0 47
ATM_attributes::
  Verbosity = high
  DumpFields = false
  ProfileMemory = false
::

# OCN = SCHISM
OCN_model:                      schism
OCN_petlist_bounds:             48 1199
OCN_attributes::
  Verbosity = high
  DumpFields = false
::

# MED = CMEPS Mediator
MED_model:                      cmeps
MED_petlist_bounds:             0 47
MED_attributes::
  Verbosity = high
  ATM_model = datm
  OCN_model = schism
  coupling_mode = coastal
::

# Run Sequence (every 120 seconds = SECOFS dt)
runSeq::
@120
  ATM -> MED :remapMethod=redist
  MED
  MED -> OCN :remapMethod=redist
  OCN
@
::
```

### 3.3 SCHISM Configuration for UFS-Coastal

SCHISM requires slight modifications for NUOPC coupling:

**File: `param.nml` additions**
```fortran
&CORE
  ! ... existing SECOFS parameters ...

  ! UFS-Coastal specific
  ics = 2           ! Coordinate system (2=lon/lat for ESMF)
/

&OPT
  ! Atmospheric forcing via NUOPC (not from files)
  nws = -1          ! -1 = receive from coupler

  ! Keep existing OBC settings
  iettype = 5
  ifltype = 5
  itetype = 5
  isatype = 5
/
```

---

## Phase 4: Validation - Match Existing SECOFS Outputs

### 4.1 Test Case: SECOFS 06z December 31, 2025

**Objective:** Run identical forcing through both systems and compare outputs.

```bash
# Directory structure
/lfs/h1/nos/ptmp/$USER/secofs_ufs_test/
├── nosofs_run/          # Current workflow output (reference)
├── ufs_run/             # UFS-Coastal output (test)
└── comparison/          # Validation scripts & results
```

### 4.2 Validation Metrics

| Metric | Tolerance | Method |
|--------|-----------|--------|
| Surface Elevation (SSH) | < 0.01 m RMSE | Compare at 49 NOAA tide stations |
| Surface Temperature | < 0.1°C RMSE | Compare at 18 NOAA T stations |
| Surface Salinity | < 0.1 PSU RMSE | Compare at 6 NOAA S stations |
| Surface Currents | < 0.05 m/s RMSE | Compare at 130 NOAA velocity stations |
| Atmospheric Forcing | Identical | Bit-for-bit comparison of input fields |

### 4.3 Validation Script

```python
# validate_secofs_ufs.py
import xarray as xr
import numpy as np

def compare_station_outputs(nosofs_file, ufs_file):
    """Compare station time series between nosofs and UFS runs"""
    ds_nosofs = xr.open_dataset(nosofs_file)
    ds_ufs = xr.open_dataset(ufs_file)

    # Compute RMSE for elevation
    rmse_elev = np.sqrt(np.mean((ds_nosofs['elevation'] - ds_ufs['elevation'])**2))

    return {
        'rmse_elevation': rmse_elev,
        'max_diff_elevation': np.abs(ds_nosofs['elevation'] - ds_ufs['elevation']).max()
    }
```

---

## Phase 5: Full UFS-Coastal Integration

### 5.1 Final Directory Structure

```
/lfs/h1/nos/nosofs/noscrub/$USER/packages/
├── ufs-coastal-app/
│   ├── sorc/
│   ├── exec/
│   │   └── ufs_coastal.x
│   └── fix/
│       └── secofs/
│           ├── secofs_esmf_mesh.nc
│           ├── secofs.hgrid.gr3
│           ├── secofs.vgrid.in
│           └── secofs.bctides.in
├── parm/
│   └── secofs/
│       ├── nems.configure
│       ├── datm_in
│       ├── datm.streams.xml
│       └── model_configure
└── jobs/
    └── JNOS_SECOFS_UFS/
```

### 5.2 Production Job Script

**File: `jnos_secofs_ufs_06.pbs`**
```bash
#!/bin/bash
#PBS -N secofs_ufs_06
#PBS -l select=10:ncpus=128:mem=500GB
#PBS -l walltime=03:00:00
#PBS -q dev

# Load UFS modules
module use /lfs/h1/nos/nosofs/noscrub/$USER/packages/ufs-coastal-app/modulefiles
module load ufs_coastal

# Set environment
export OFS=secofs
export cyc=06
export PDY=20251231

# Run prep (existing scripts for OBC, river)
$USHnos/nos_ofs_create_forcing_obc.sh
$USHnos/nos_ofs_create_forcing_river.sh

# Prepare DATM streams (new)
$USHnos/prepare_datm_streams.sh

# Run UFS-Coastal
cd $DATA
mpiexec -n 1200 ./ufs_coastal.x

# Post-processing
$USHnos/nos_ofs_archive.sh
```

---

## Phase 6: Timeline & Milestones

### Milestone 1: Build & Basic Test (Week 1-2)
- [ ] Clone and build UFS-Coastal on WCOSS2
- [ ] Run Shinnecock Inlet test case (built-in)
- [ ] Verify DATM+SCHISM coupling works

### Milestone 2: SECOFS Grid Conversion (Week 3-4)
- [ ] Convert secofs.hgrid.gr3 to ESMF mesh
- [ ] Create SCRIP weight files for GFS → SECOFS remapping
- [ ] Test with simple tidal forcing

### Milestone 3: DATM Configuration (Week 5-6)
- [ ] Configure DATM streams for GFS 0.25°
- [ ] Configure DATM streams for HRRR 3km
- [ ] Test atmospheric forcing ingestion

### Milestone 4: Full SECOFS 06z Test (Week 7-8)
- [ ] Run parallel nosofs vs UFS-Coastal
- [ ] Validate station outputs
- [ ] Document differences

### Milestone 5: Production Integration (Week 9-12)
- [ ] Integrate with existing OBC/river scripts
- [ ] Create production job scripts
- [ ] Performance optimization
- [ ] Documentation

---

## Key Differences: nosofs vs UFS-Coastal

| Aspect | nosofs (Current) | UFS-Coastal (Target) |
|--------|------------------|----------------------|
| **Atm Forcing** | Fortran interpolation to SCHISM grid | DATM reads native grid, CMEPS remaps |
| **Coupling** | File-based (sflux_*.nc) | Memory-based via NUOPC |
| **Executable** | pschism_WCOSS2 | ufs_coastal.x |
| **Grid Format** | gr3/hgrid | ESMF mesh |
| **Mediator** | None | CMEPS |
| **Parallelization** | SCHISM MPI only | ESMF component decomposition |
| **Flexibility** | Fixed workflow | Modular, extensible |

---

## Resources & References

### Documentation
- [UFS-Coastal Application ReadTheDocs](https://ufs-coastal-application.readthedocs.io/)
- [CDEPS DATM Documentation](https://escomp.github.io/CDEPS/versions/master/html/datm.html)
- [ESMF/NUOPC Documentation](https://earthsystemmodeling.org/docs/)

### Repositories
- [UFS-Coastal App](https://github.com/oceanmodeling/ufs-coastal-app)
- [UFS-Weather-Model (Coastal Fork)](https://github.com/oceanmodeling/ufs-weather-model)
- [CoastalApp Test Suite](https://github.com/schism-dev/CoastalApp-testsuite)

### Contacts
- UFS-Coastal Team: NOS Storm Surge Modeling Team
- SCHISM: Y. Joseph Zhang (yjzhang@vims.edu)
- ESMF/NUOPC: NCAR ESMF Team

---

## Appendix A: Quick Reference Commands

```bash
# Build UFS-Coastal
cd ufs-coastal-app/sorc
CMAKE_FLAGS="-DAPP=CSTL -DCOASTAL_SCHISM=ON -DCDEPS_DATM=ON" ./build.sh

# Convert SCHISM grid to ESMF mesh
ESMF_Scrip2Unstruct secofs_scrip.nc secofs_esmf_mesh.nc 0

# Run UFS-Coastal
mpiexec -n 1200 ./ufs_coastal.x

# Validate outputs
python validate_secofs_ufs.py --ref nosofs_run --test ufs_run
```

---

*Plan created: January 2, 2026*
*Target completion: Q1 2026*
