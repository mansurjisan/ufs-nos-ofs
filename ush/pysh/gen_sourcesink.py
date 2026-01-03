import os
os.environ['USE_PYGEOS'] = '0'
import geopandas

from datetime import datetime
from time import time
import pathlib
import logging

import gsw as sw

#from pyschism.forcing.source_sink.nwm import NationalWaterModel, NWMElementPairings
#from pyschism.mesh import Hgrid


from nwm import NationalWaterModel, NWMElementPairings

from  hgrid import Hgrid


logging.basicConfig(
    format="[%(asctime)s] %(name)s %(levelname)s: %(message)s",
    force=True,
)
logging.captureWarnings(True)

log_level = logging.DEBUG
logging.getLogger('pyschism').setLevel(log_level)

#logging.basicConfig(level=logging.INFO)  #  machuan added 

#########
#file_in = open('timestamp', 'r')
#a, b, c, d, e = file_in.read().splitlines()


#yyyy=int(a)
#mm=int(b)
#dd=int(c)
#hh=int(d)
#hlength=int(e)
###############

if __name__ == '__main__':

    startdate = datetime(2025,5,12,0)
    rnday = 24.0/24.0
    hhgrid = Hgrid.open("./hgrid.gr3", crs="epsg:4326")  ##  changed to hhgrid just make it different from hgrid

    t0 = time()

    #source/sink json files, if not exist, it will call NWMElementPairings to generate.
    sources_pairings = pathlib.Path('./sources.json')
    sinks_pairings = pathlib.Path('./sinks.json')
    output_directory = pathlib.Path('./data')

    #input directory which saves nc files
    cache = pathlib.Path('./')

    # check if source/sink json file exists
    if all([sources_pairings.is_file(), sinks_pairings.is_file()]) is False:
        pairings = NWMElementPairings(hhgrid)  ##  it takes about 20 minutes for secofs for this step
        sources_pairings.parent.mkdir(exist_ok=True, parents=True)
        pairings.save_json(sources=sources_pairings, sinks=sinks_pairings)
    else:
        pairings = NWMElementPairings.load_json(
            hhgrid, 
            sources_pairings, 
            sinks_pairings)
           
    #check nc files, if not exist will download
    nwm=NationalWaterModel(pairings=pairings, cache=cache)

    nwm.write(output_directory, hhgrid, startdate, rnday, overwrite=True)
    print(f'It took {time()-t0} seconds to generate source/sink')
