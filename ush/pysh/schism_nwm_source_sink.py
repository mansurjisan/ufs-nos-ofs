import os
os.environ['USE_PYGEOS'] = '0'
import geopandas

from datetime import datetime, timedelta  # XC ADDED
from time import time
import pathlib
import logging

import gsw as sw

# from pyschism.forcing.source_sink.nwm import NationalWaterModel, NWMElementPairings
# from pyschism.mesh import Hgrid

from nwm import NationalWaterModel, NWMElementPairings
from hgrid import Hgrid
from netCDF4 import Dataset  # XC ADDED

from local_inventory import LocalNWMInventory

logging.basicConfig(
    format="[%(asctime)s] %(name)s %(levelname)s: %(message)s",
    force=True,
)
logging.captureWarnings(True)

log_level = logging.DEBUG
logging.getLogger('pyschism').setLevel(log_level)

# logging.basicConfig(level=logging.INFO)  # machuan added




#########
with open('nwm_source_sink_timestamp', 'r') as file:  ##  the file is from script
    time_start=file.readline()
    time_end=file.readline()

yyyys=int(time_start[0:4])
mms=int(time_start[4:6])
dds=int(time_start[6:8])
hhs=int(time_start[8:10])


yyyye=int(time_end[0:4])
mme=int(time_end[4:6])
dde=int(time_end[6:8])
hhe=int(time_end[8:10])


if __name__ == '__main__':

    startdate = datetime(yyyys, mms, dds, hhs, 0)  # XC ADDED: adjusted to match t06z start time
    # rnday = 0.2  # XC ADDED: adjust if needed
    enddate   = datetime(yyyye, mme, dde, hhe, 0)  # 


    hhgrid = Hgrid.open("./hgrid.gr3", crs="epsg:4326")  ## changed to hhgrid just make it different from hgrid

    t0 = time()

    sources_pairings = pathlib.Path('./sources.json')
    sinks_pairings = pathlib.Path('./sinks.json')
    output_directory = pathlib.Path('./data')

    # input directory which saves nc files

    cache = pathlib.Path('./nwm_harvest')  # the dir name and the files inside from script

    # check if source/sink json file exists
    if all([sources_pairings.is_file(), sinks_pairings.is_file()]) is False:
        pairings = NWMElementPairings(hhgrid)  ## it takes about 20 minutes for secofs for this step
        sources_pairings.parent.mkdir(exist_ok=True, parents=True)
        pairings.save_json(sources=sources_pairings, sinks=sinks_pairings)
    else:
        pairings = NWMElementPairings.load_json(
            hhgrid,
            sources_pairings,
            sinks_pairings)

    # check nc files, if not exist will download
    # nwm = NationalWaterModel(pairings=pairings, cache=cache)  # COMMENTED

    # === XC ADDED: Load local nc files by priority ===
#    nc_patterns = [
#        'nwm.t*z.analysis_assim.channel_rt.tm02.conus.nc',
#        'nwm.t11z.short_range.channel_rt.f*.conus.nc',
#        'nwm.t06z.medium_range.channel_rt_1.f*.conus.nc',
#    ]

    nc_patterns = [
            'nwm_*.nc'   #  renamd file names from script
    ]

    found_files = None
    for pattern in nc_patterns:
        candidate_files = sorted(cache.glob(pattern))
        if candidate_files:
            print(f"[XC] Found {len(candidate_files)} files using pattern: {pattern}")
            found_files = candidate_files
            break
        else:
            print(f"[XC] No files found for pattern: {pattern}")

    if found_files is None:
        raise FileNotFoundError(f"[XC] No NWM .nc files found in {cache} for any supported pattern.")

    # use found files to construct LocalNWMInventory
    nwm = NationalWaterModel(pairings=pairings, cache=cache)
    #nwm._inventory = LocalNWMInventory(found_files)
    nwm._inventory = LocalNWMInventory(found_files, start_date=startdate, end_date=enddate)


    """ 
    # === XC ADDED: Load local nc files ===
    nc_files = sorted(cache.glob('nwm.t06z.medium_range.channel_rt_1.f*.conus.nc'))  # XC ADDED
    if len(nc_files) == 0:  # XC ADDED
        raise FileNotFoundError(f"[XC] No NWM .nc files found in {cache}")  # XC ADDED

    nwm = NationalWaterModel(pairings=pairings, cache=cache)  # XC ADDED
    nwm._inventory = LocalNWMInventory(nc_files)  # XC ADDED

    """

    nwm.write(output_directory, hhgrid, start_date=startdate, end_date=enddate, overwrite=True)
    print(f'It took {time()-t0} seconds to generate source/sink')
