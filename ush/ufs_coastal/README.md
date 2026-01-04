# UFS-Coastal Integration Scripts

Operational scripts for integrating UFS-Coastal CDEPS DATM into the nosofs/SECOFS workflow.

## Overview

These scripts generate ESMF mesh files and UFS configuration files required for running SCHISM with the UFS-Coastal framework using CDEPS DATM (Data Atmosphere) instead of traditional sflux forcing.

## Scripts

### Main Scripts

| Script | Purpose |
|--------|---------|
| `nos_ofs_create_esmf_mesh.sh` | Generate ESMF mesh from GFS/HRRR GRIB2 data |
| `nos_ofs_gen_ufs_config.sh` | Generate UFS config files from templates |
| `modify_gfs_nco.sh` | Add CF attributes to GFS NetCDF (NCO method) |
| `modify_hrrr_nco.sh` | Add CF attributes to HRRR NetCDF (NCO method) |

### Python Scripts (pysh/)

| Script | Purpose |
|--------|---------|
| `modify_gfs_4_esmfmesh.py` | Add CF attributes to GFS NetCDF (Python method) |
| `modify_hrrr_4_esmfmesh.py` | Add CF attributes to HRRR NetCDF (Python method) |
| `proc_scrip.py` | Generate SCRIP grid files (replaces NCL) |

## Usage

### Enable in Workflow

Add to `secofs.ctl`:
```bash
export GENERATE_ESMF_MESH=true
```

### Standalone Testing

```bash
# Generate GFS ESMF mesh
./nos_ofs_create_esmf_mesh.sh GFS25 /path/to/gfs.pgrb2.0p25.f000 ./output

# Generate HRRR ESMF mesh
./nos_ofs_create_esmf_mesh.sh HRRR /path/to/hrrr.wrfsfcf00.grib2 ./output

# Generate UFS config files
export PDY=20260103 cyc=06 DATA=/path/to/workdir FIXofs=/path/to/fix
./nos_ofs_gen_ufs_config.sh
```

## Output Files

| File | Description |
|------|-------------|
| `gfs_esmf_mesh.nc` | ESMF mesh for GFS grid |
| `hrrr_esmf_mesh.nc` | ESMF mesh for HRRR grid |
| `gfs_for_esmf.nc` | GFS data with CF attributes |
| `hrrr_for_esmf.nc` | HRRR data with CF attributes |
| `model_configure` | UFS model configuration |
| `datm_in` | DATM namelist |
| `datm.streams` | DATM stream definitions |
| `ufs.configure` | NUOPC run sequence |

## Dependencies

- wgrib2 (GRIB2 to NetCDF conversion)
- ESMF_Scrip2Unstruct (SCRIP to ESMF mesh)
- NCO tools (ncatted) - preferred method on WCOSS2
- Python 3 with xarray, netCDF4 - fallback method

## WCOSS2 Notes

The scripts automatically use NCO tools (`ncatted`) on WCOSS2 for reliability.
If using Python, `LD_PRELOAD` is automatically unset to avoid netCDF library conflicts.

## Related Documentation

- [SECOFS_UFS_COASTAL_TRANSITION.md](../../docs/SECOFS_UFS_COASTAL_TRANSITION.md)
- [WCOSS2_UFS_TESTING.md](../../docs/WCOSS2_UFS_TESTING.md)
