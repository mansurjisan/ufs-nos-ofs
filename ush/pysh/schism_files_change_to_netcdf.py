from scipy.io import FortranFile
import netCDF4 as nc
import numpy as np

#from scipy.io import FortranFile
#f = FortranFile( 'temp_nu.in', 'r' )
#a = f.read_reals( dtype='float32' )


#with open('bin_file_dimension_ctl', 'r') as file:
#   next(file)
#   for line in file:
#        lines = [i for i in line.split( )]
#        ts=lines[0]

with open('bin_file_dimension_ctl', 'r') as file:
   next(file)
   for line in file:
        lines = [i for i in line.split( )]
        ntimest=int(lines[0])
        nnodest=int(lines[1])
        kbm=int(lines[2])
        ntimewl=int(lines[3])
        nnodewl=int(lines[4])

        delt_ts=lines[5]
        delt_wl=lines[6]



temp = np.zeros((ntimest,nnodest,kbm))
salt = np.zeros((ntimest,nnodest,kbm))
timest = np.zeros(ntimest)

tempnobc = np.zeros((ntimest,nnodewl,kbm))
saltnobc = np.zeros((ntimest,nnodewl,kbm))
nunode = np.zeros(nnodest)

timewl = np.zeros(ntimewl)
time = np.zeros(ntimewl)
wl = np.zeros((ntimewl,nnodewl))




with open('temp_nu.in', 'r') as f:
        data = f.read().split()
        dtemp = []   # all data
        for elem in data:
            try:
                dtemp.append(float(elem))
            except ValueError:
                pass

with open('salt_nu.in', 'r') as f:
        data = f.read().split()
        dsalt = []   # all data
        for elem in data:
            try:
                dsalt.append(float(elem))
            except ValueError:
                pass


for nt in range(ntimest):
    print(nt)
    k=int(nt*nnodest*kbm)
    timest[nt]=dtemp[nt+k]
    for nn in range(nnodest):
        for nk in range(kbm):
           nall=k+nk+nn*kbm+nt+1
           temp[nt][nn][nk]=dtemp[nall]
           salt[nt][nn][nk]=dsalt[nall]



nobc=[]
nunode=[]
#tempnobc=[]
#saltnobc=[]



for line in open('nobc_nudge_index.dat', 'r'):
    lines = [i for i in line.split( )]
    nobc.append(int(lines[0]))



for line in open('nudge_point_at_ofs_grid.dat', 'r'):
        lines = [i for i in line.split( )]
        nunode.append(int(lines[1]))



for nt in range(ntimest):
#    k=int(nt*nnodest*kbm)
#    timest[nt]=dtemp[nt+k]
    for nn in range(nnodewl):
        nnn=nobc[nn]
        for nk in range(kbm):
            tempnobc[nt][nn][nk]=temp[nt][nnn-1][nk]
            saltnobc[nt][nn][nk]=salt[nt][nnn-1][nk]



from  netCDF4 import Dataset

ncfile = Dataset('TEM_nu.nc',mode='w',format='NETCDF4_CLASSIC')
time_dim = ncfile.createDimension('time', ntimest)
node_dim = ncfile.createDimension('node', nnodest)
nLevels_dim = ncfile.createDimension('nLevels', kbm)
one_dim = ncfile.createDimension('one', 1)


time = ncfile.createVariable('time', np.double, ('time',))
map_to_global_node =  ncfile.createVariable('map_to_global_node', np.int32, ('node'))
tracer_concentration = ncfile.createVariable('tracer_concentration', np.float64, ('time','node','nLevels','one'))


time[:] = timest
map_to_global_node[:] = nunode
tracer_concentration[:,:,:,0]= temp

ncfile.close()


ncfile = Dataset('SAL_nu.nc',mode='w',format='NETCDF4_CLASSIC')
time_dim = ncfile.createDimension('time', ntimest)
node_dim = ncfile.createDimension('node', nnodest)
nLevels_dim = ncfile.createDimension('nLevels', kbm)
one_dim = ncfile.createDimension('one', 1)


time = ncfile.createVariable('time', np.double, ('time',))
map_to_global_node =  ncfile.createVariable('map_to_global_node', np.int32, ('node'))
tracer_concentration = ncfile.createVariable('tracer_concentration', np.float64, ('time','node','nLevels','one'))


time[:] = timest
map_to_global_node[:] = nunode
tracer_concentration[:,:,:,0]= salt

ncfile.close()


ncfile = Dataset('TEM_3D.th.nc',mode='w',format='NETCDF4_CLASSIC')

time_dim = ncfile.createDimension('time', ntimest)
nComponents_dim = ncfile.createDimension('nComponents', 1)
nOpenBndNodes_dim = ncfile.createDimension('nOpenBndNodes', nnodewl)
nLevels_dim = ncfile.createDimension('nLevels', kbm)
one_dim = ncfile.createDimension('one', 1)

time = ncfile.createVariable('time', np.double, ('time',))
time_step = ncfile.createVariable('time_step', np.double, ('one',))
time_series = ncfile.createVariable('time_series', np.float64, ('time','nOpenBndNodes','nLevels','one'))

time_step[:]=delt_ts
time[:] = timest
time_series[:,:,:,0]= tempnobc

ncfile.close()

ncfile = Dataset('SAL_3D.th.nc',mode='w',format='NETCDF4_CLASSIC')
time_dim = ncfile.createDimension('time', ntimest)
nComponents_dim = ncfile.createDimension('nComponents', 1)
nOpenBndNodes_dim = ncfile.createDimension('nOpenBndNodes', nnodewl)
nLevels_dim = ncfile.createDimension('nLevels', kbm)
one_dim = ncfile.createDimension('one', 1)

time = ncfile.createVariable('time', np.double, ('time',))
time_step = ncfile.createVariable('time_step', np.double, ('one',))
time_series = ncfile.createVariable('time_series', np.float64, ('time','nOpenBndNodes','nLevels','one'))

time_step[:]=delt_ts
time[:] = timest
time_series[:,:,:,0]= saltnobc

ncfile.close()




with open('elev3D.th', 'r') as f:
        data = f.read().split()
        dwl = []   # all data
        for elem in data:
            try:
                dwl.append(float(elem))
            except ValueError:
                pass


for nt in range(ntimewl):
    k=int(nt*nnodewl)
    timewl[nt]=dwl[nt+k]
    for nn in range(nnodewl):
           nall=k+nn+nt+1
           wl[nt][nn]=dwl[nall]



ncfile = Dataset('elev2D.th.nc',mode='w',format='NETCDF4_CLASSIC')


time_dim = ncfile.createDimension('time', ntimewl)
nComponents_dim = ncfile.createDimension('nComponents', 1)
nOpenBndNodes_dim = ncfile.createDimension('nOpenBndNodes', nnodewl)
nLevels_dim = ncfile.createDimension('nLevels', 1)
one_dim = ncfile.createDimension('one', 1)

time = ncfile.createVariable('time', np.float32, ('time'))
time_step = ncfile.createVariable('time_step', np.float32, ('one'))
time_series = ncfile.createVariable('time_series', np.float32, ('time','nOpenBndNodes','nLevels','one'))

time_step[:]=delt_wl
time[:] = timewl
time_series[:,:,0,0]= wl


ncfile.close()

time_series = np.zeros((ntimewl,nnodest,kbm,2))

ncfile = Dataset('uv3D.th.nc',mode='w',format='NETCDF4_CLASSIC')
time_dim = ncfile.createDimension('time', ntimest)
nComponents_dim = ncfile.createDimension('nComponents', 2)
nOpenBndNodes_dim = ncfile.createDimension('nOpenBndNodes', nnodewl)
nLevels_dim = ncfile.createDimension('nLevels', kbm)
one_dim = ncfile.createDimension('one', 1)


time = ncfile.createVariable('time', np.double, ('time',))
time_step = ncfile.createVariable('time_step', np.double, ('one',))
time_series = ncfile.createVariable('time_series', np.float64, ('time','nOpenBndNodes','nLevels','nComponents'))


time_step[:]=delt_ts
time[:] = timest

time_series[:,:,:,:]= 0.0










