import shutil
import netCDF4 as nc
from netCDF4 import Dataset
import subprocess
import os
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.tri as tri

cfile = "schism_standard_output.ctl"
with open(cfile, 'r') as file:
        lines = [line.strip() for line in file.readlines()]


PREFIXNOS=lines[0]
cyc=lines[1]
day=lines[2]
mode=lines[3]
timestart=lines[4]

yyyy= timestart[0:4]
mm = timestart[4:6]
dd = timestart[6:8]
hh = timestart[8:10]


data = np.loadtxt('secofs.sigma.dat', dtype=float)  ## this file must be copied to working dir
sigma1=data.T


nvfile=f"{PREFIXNOS}.nv.nc"  ###  now the nv dimensional is in correct order

print(nvfile)

ds_nv=nc.Dataset(nvfile)
nv1=ds_nv.variables["nv"][:]


for i in range(1,48):
    ii = f"{i:03d}"
    print(ii)
#    file2d=f"secofs.t{cyc}z.{day}.out2d.n{ii}.nc"
#    filetemp=f"secofs.t{cyc}z.{day}.temperature.n{ii}.nc"
#    filesalt=f"secofs.t{cyc}z.{day}.salinity.n{ii}.nc"
    file2d=f"out2d_{i}.nc"
    filetemp=f"temperature_{i}.nc"
    filesalt=f"salinity_{i}.nc"
    fileu=f"horizontalVelX_{i}.nc"
    filev=f"horizontalVelY_{i}.nc"

    filenv='secofs.nv.nc'

    ds_filenv = nc.Dataset(filenv)

    nv1 = ds_filenv.variables["nv"][:]

    if not os.path.exists(file2d):
        break 
    else:
        print(file2d)
        
        ds_grid = nc.Dataset(file2d)
        ds_temp = nc.Dataset(filetemp)
        ds_salt = nc.Dataset(filesalt)
        ds_u = nc.Dataset(fileu)
        ds_v = nc.Dataset(filev)

        time1 = ds_grid.variables["time"][:]


        zeta1 = ds_grid.variables["elevation"][:]
        nstep = len(time1)
        
        print(nstep)

        h1= ds_grid.variables["depth"][:]

        x1 = ds_grid.variables["SCHISM_hgrid_node_x"][:]

        lon1 = ds_grid.variables["SCHISM_hgrid_node_x"][:]
        lat1 = ds_grid.variables["SCHISM_hgrid_node_y"][:]
        uwind1 = ds_grid.variables["windSpeedX"][:]
        vwind1 = ds_grid.variables["windSpeedY"][:]

        temp1 = ds_temp.variables["temperature"][:]
        salt1 = ds_salt.variables["salinity"][:]
        u1 = ds_u.variables["horizontalVelX"][:]
        v1 = ds_v.variables["horizontalVelY"][:]

        print("= mode===", mode)

        if mode == "n":
            shutil.copyfile("out2d_1.nc", f"secofs.t{cyc}z.{day}.out2d_1.nowcast.nc")
            shutil.copyfile("zCoordinates_1.nc", f"secofs.t{cyc}z.{day}.zCoordinates_1.nowcast.nc")
            shutil.copyfile("temperature_1.nc", f"secofs.t{cyc}z.{day}.temperature_1.nowcast.nc")
            shutil.copyfile("salinity_1.nc", f"secofs.t{cyc}z.{day}.salinity_1.nowcast.nc")
            shutil.copyfile("horizontalVelX_1.nc", f"secofs.t{cyc}z.{day}.horizontalVelX_1.nowcast.nc")
            shutil.copyfile("horizontalVelY_1.nc", f"secofs.t{cyc}z.{day}.horizontalVelY_1.nowcast.nc")
            for k in range(1,9):
                file= f"staout_{k}"
                nfile= f"secofs.t{cyc}z.{day}.nowcast.staout_{k}"
                shutil.copyfile(file, nfile)


        for k in range(0,nstep):
            iii=(i-1)*nstep+k+1
            kkk = f"{iii:03d}"

#            nfields=f"secofs.t{cyc}z.{day}.fields.{mode}{kkk}.nc"
            nfields=f"secofs.t{cyc}z.{day}.fields.{mode}{kkk}.nc.old"

            print(nfields)

            ncfile = Dataset(nfields,mode='w',format='NETCDF4_CLASSIC')

            node_dim = ncfile.createDimension('node',1684786)
            nele_dim = ncfile.createDimension('nele',3332737)  ##  note this value is more than the original 3322329
            nface_dim = ncfile.createDimension('nface', 3)
            nv_dim = ncfile.createDimension('nv', 63)
#            simga_dim = ncfile.createDimension('sigma', 46)
#            nz_dim = ncfile.createDimension('nz', 17)
            time_dim =  ncfile.createDimension('time', None)


            lon = ncfile.createVariable('lon', np.float32, ('node'))
            lat = ncfile.createVariable('lat', np.float32, ('node'))
            time = ncfile.createVariable('time', np.float32, ('time'))
            time.units = f"seconds since {yyyy}-{mm}-{dd} {hh}:00:00"

            ele = ncfile.createVariable('ele', 'i4', ('nface','nele'))  ## Triangular Element Table
            h = ncfile.createVariable('h', np.float32, ('node'))
#            z = ncfile.createVariable('z', np.float32, ('nz'))  
#            sigma =  ncfile.createVariable('sigma', np.float32, ('sigma'))

#            sigma_z = ncfile.createVariable('sigma_z', np.float32, ('nv')) 



            zeta = ncfile.createVariable('zeta', np.float32, ('time','node'))
            uwind_speed = ncfile.createVariable('uwind_speed', np.float32, ('time','node'))
            vwind_speed = ncfile.createVariable('Vwind_speed', np.float32, ('time','node'))


            temp = ncfile.createVariable('temp', np.float32, ('time','nv','node'))
            salinity = ncfile.createVariable('salinity', np.float32, ('time','nv','node'))

            u = ncfile.createVariable('u', np.float32, ('time','nv','node'))
            v = ncfile.createVariable('v', np.float32, ('time','nv','node'))

            sigma = ncfile.createVariable('sigma', np.float32, ('node','nv'))


            h[:] = h1[:]
            lon[:] = lon1[:] 
            lat[:] = lat1[:]
            ele[:,:] = nv1[:,:]
            sigma[:,:]=sigma1[:,:]

#            z[:] = -5000, -2300, -1800, -1400, -1000, -770, -570, -470, -390, -340, -290, -240, -190, -140, -120, -110, -105 


#            for kk in range(46):
#                sigma[kk]= - (46.0-kk)/46.0

#            for kk in range(63):
#                sigma_z[kk]= -(63.0-kk)/63.0 
            
            time[:] = time1[k]


            zeta[0,:] = zeta1[k,:]
            uwind_speed[0,:] = uwind1[k,:]
            vwind_speed[0,:] = vwind1[k,:]

            temp[0,:,:] = temp1[k,:,:].T
            salinity[0,:,:] = salt1[k,:,:].T
            u[0,:,:] = u1[k,:,:].T
            v[0,:,:] = v1[k,:,:].T

            ncfile.close()
            
            nfieldsn=f"secofs.t{cyc}z.{day}.fields.{mode}{kkk}.nc"
            ncks_command = [ "ncks", "-4", "-L", "4", nfields, nfieldsn ] ## higher deflation level is too slow
			
            try:
                subprocess.check_call(ncks_command)
            except subprocess.CalledProcessError as e:
                print(f"Error executing NCO command: {e}")
            except FileNotFoundError:
                print("Error: 'ncks' command not found. Ensure NCO is installed and in your PATH.")


####  station files


# staout_[1..,9] represent elev, air pressure, wind u, wind v, T, S, u, v, w
#  staout_1 , 2 3, 4, 5 ,6, 7, 8  for SECOFS

if PREFIXNOS == "secofs":
    nsta=271 # vims original
    nsta2=nsta*2
    nver=63


ele_values = []
uwind_values = []
vwind_values = []
temp_values = []
salt_values = []
u_values = []
v_values = []


outindex1 = [ 1, 3, 4 ]
for ind in outindex1:
    file_name=f"staout_{ind}"
    all_numbers_from_file = []
    first_column = []
    time_values = []
#    variable_values = []
    nline=0

    with open(file_name, 'r') as file:
        for line in file:
            nline = nline+1
            number_strings = line.strip().split()
            numbers_on_line = [float(num_str) for num_str in number_strings]
            all_numbers_from_file.append(numbers_on_line)

    arr = np.array(all_numbers_from_file)
    time_values = arr[:,0]

    if ind == 1:
        ele_values = arr[:,1:nsta+1]
    if ind == 3:
        uwind_values = arr[:,1:nsta+1]
    if ind == 4:
        vwind_values = arr[:,1:nsta+1]


outindex2 = [ 5 ,6, 7, 8 ]

for ind in outindex2:
    file_name=f"staout_{ind}"
    all_numbers_from_file = []
    first_column = []
    time_values = []
#    variable_values = []
    nline=0

    with open(file_name, 'r') as file:
        for line in file:
            nline = nline+1
            if nline % 2 == 0:
                number_strings = line.strip().split()
                numbers_on_line = [float(num_str) for num_str in number_strings]
                all_numbers_from_file.append(numbers_on_line)

    arr = np.array(all_numbers_from_file)
    time_values = arr[:,0]
    nstep=len(time_values)

    if ind == 5:
        temp0 = arr[:,1:]
        temp_value = temp0.reshape(nstep,nsta2,nver)
        temp_value_real = temp_value[:,0:nsta,:]
        temp_value_real_final = np.swapaxes(temp_value_real,1,2)

    if ind == 6:
        salt0 = arr[:,1:]
        salt_value = salt0.reshape(nstep,nsta2,nver)
        salt_value_real = salt_value[:,0:nsta,:]
        salt_value_real_final = np.swapaxes(salt_value_real,1,2)

    if ind == 7:
        u0 = arr[:,1:]
        u_value = u0.reshape(nstep,nsta2,nver)
        u_value_real = u_value[:,0:nsta,:]
        u_value_real_final = np.swapaxes(u_value_real,1,2)

    if ind == 8:
        v0 = arr[:,1:]
        v_value = v0.reshape(nstep,nsta2,nver)
        v_value_real = v_value[:,0:nsta,:]
        v_value_real_final = np.swapaxes(v_value_real,1,2)


if mode == "n":
    modefull = "nowcast"
if mode == "f":
    modefull = "forecast"

filesta=f"{PREFIXNOS}.t{cyc}z.{day}.stations.{modefull}.nc"
ncfile = Dataset(filesta,mode='w',format='NETCDF4')
name_length = 20


station_dim = ncfile.createDimension('station',nsta )
clen_dim = ncfile.createDimension('clen', name_length )


time_dim = ncfile.createDimension('time',nstep )

siglay_dim = ncfile.createDimension('siglay',nver )


time = ncfile.createVariable('time', np.float32, ('time'))
time.units = f"seconds since {yyyy}-{mm}-{dd} {hh}:00:00"

lon = ncfile.createVariable('lon', np.float32, ('station'))
lat = ncfile.createVariable('lat', np.float32, ('station'))

num_strings_dim_name = 'num_entries'
num_entries = nsta
ncfile.createDimension(num_strings_dim_name, num_entries)

name_station_var = ncfile.createVariable('name_station', 'S1', ('station','clen'))


zeta = ncfile.createVariable('zeta', np.float32, ('time','station'))
uwind = ncfile.createVariable('uwind_speed', np.float32, ('time','station'))
vwind = ncfile.createVariable('vwind_speed', np.float32, ('time','station'))



temp = ncfile.createVariable('temp', np.float32, ('time','siglay','station'))
salinity = ncfile.createVariable('salinity', np.float32, ('time','siglay','station'))

u = ncfile.createVariable('u', np.float32, ('time','siglay','station'))
v = ncfile.createVariable('v', np.float32, ('time','siglay','station'))




file_name = "secofs.station.lat.lon"

name_station = []


all_from_file = []
lon_values = []
lat_values = []


with open(file_name, 'r') as file:
    for line in file:
        number_strings = line.strip().split()
        all_from_file.append(number_strings)



arr = np.array(all_from_file)

#for i in range(nsta):
#    station_names = f"Station_{i+1:03d}"

station_names = [f'station_secofs_{i+1:05d}' for i in range(nsta)] # Example names

names_char_array = nc.stringtochar(np.array(station_names, dtype=f'S{name_length}'))
name_station_var[:] = names_char_array


lon_values = arr[:,1]
lat_values = arr[:,2]

time[:] = time_values[:]
lon[:] = lon_values[:]
lat[:] = lat_values[:]
zeta[:,:] = ele_values[:,:]

uwind[:,:] = uwind_values[:,:]
vwind[:,:] = vwind_values[:,:]

#temp[:,:] = temp_values[:,:]
#salinity[:,:] = salt_values[:,:]

temp[:,:,:] = temp_value_real_final[:,:,:]
salinity[:,:,:] = salt_value_real_final[:,:,:]
u[:,:,:] = u_value_real_final[:,:,:]
v[:,:,:] = v_value_real_final[:,:,:]


































