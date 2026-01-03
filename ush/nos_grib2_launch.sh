#!/bin/sh
# Script Name:   nos_grib2_launch.sh                                           
#
#### END of Unix Script DOC BLOCK--------------------------------------------------- 
set -x


echo 'The script nos_grib2_launch.sh has started at UTC' `date `
echo 'The script nos_grib2_launch.sh has started at UTC' `date ` >> $cormslogfile 
echo 'The script nos_grib2_launch.sh has started at UTC' `date ` >> $jlogfile 
echo 'The script nos_grib2_launch.sh has started at UTC' `date ` >> $nosjlogfile 

#################################################################
# Run setup to initialize working directory and utility scripts
# Run setpdy and initialize PDY variables
#################################################################

# set from system PDY variable for operations
export time_nowcastend=$PDY${cyc}

#------------------------------------------------'
#  COPY Files into Work Directory
#------------------------------------------------' 


echo "============ mmgp FIXofs ====" $FIXofs 

cp  $FIXofs/*.out ./

 YYYY=`echo $time_nowcastend | cut -c1-4 `
   MM=`echo $time_nowcastend | cut -c5-6 `
   DD=`echo $time_nowcastend | cut -c7-8 `
   HH=`echo $time_nowcastend | cut -c9-10 `

 if [ $cyc -ge 6 ]; then

 YYYYm3=$YYYY
   MMm3=$MM
   DDm3=$DD
   HH3=`expr ${HH} - 3 `
   HHm3=$(printf "%02d" $HH3)


  else

time_now=` $NDATE  `

	echo "=== time_now ==", $time_now

   HHm3=`echo $time_now | cut -c9-10 `

        echo "=== HHm3 ==", $HHm3

	hhm3m=`expr ${HHm3} + 3`

export time_nowcastendm3=` $NDATE -${hhm3m} `

echo "==== mmgp === time_nowcastendm3 ==" $time_nowcastendm3

 YYYYm3=`echo $time_nowcastendm3 | cut -c1-4 `
   MMm3=`echo $time_nowcastendm3 | cut -c5-6 `
   DDm3=`echo $time_nowcastendm3 | cut -c7-8 `
   HHm3=`echo $time_nowcastendm3 | cut -c9-10 `

fi



echo "====== mmgp === time_nowcastend ==", $time_nowcastend
echo "==== mmgp == COMROOT ==",$COMROOT

#export COMIN=$COMROOT/nos/prod

export COMIN=/lfs/h1/ops/prod/com/nosofs/v3.6



echo "==== mmgp == COMIN ==",$COMIN


##for ofs in gomofs cbofs dbofs tbofs ciofs leofs lmhofs
for ofs in cbofs gomofs 

 
do

cominday=$COMIN/${ofs}.$YYYY$MM$DD

echo $ofs >> fields_files_${ofs}.in


##echo $ofs >> fields_files_${ofs}.in

##if [ $ofs == "lmhofs" -o $ofs == "leofs" ]; then
##echo fvcom >> grib2_${ofs}.in
##else
##echo roms >> grib2_${ofs}.in
##fi


#echo $COMIN >>  grib2_${ofs}.in
#echo $time_nowcastend  >>  grib2_${ofs}.in

echo $cominday/$ofs.t${HH}z.$YYYY$MM$DD.fields.n006.nc  >>  fields_files_${ofs}.in

   N=0
   while (( N <= 45 ))  ###  need to be 45 rather than 48
   do
  N=`expr $N + 3`

nnn=$(printf "%03d" $N)

#echo $cominday/nos.$ofs.fields.f${nnn}.$YYYY$MM$DD.t${HH}z.nc  >>  fields_files_${ofs}.in
echo $cominday/$ofs.t${HH}z.$YYYY$MM$DD.fields.f${nnn}.nc   >>  fields_files_${ofs}.in


    done

done



##for ofs in sfbofs ngofs 

for ofs in sfbofs ngofs

do

echo $ofs  >> fields_files_${ofs}.in


## echo $ofs >> grib2_${ofs}.in
## echo fvcom >> grib2_${ofs}.in

   N=0
   while (( N <= 48 ))
   do
  N=`expr $N + 3`

nnn=$(printf "%03d" $N)

comindaym3=$COMIN/${ofs}.$YYYYm3$MMm3$DDm3


echo $comindaym3/nos.$ofs.fields.f${nnn}.$YYYYm3$MMm3$DDm3.t${HHm3}z.nc  >>  fields_files_${ofs}.in

    done




done


###  ofs_project_back_to_grib2_conus625m


####for ofs in cbofs gomofs ngofs sfbofs
for ofs in cbofs gomofs ngofs sfbofs


do

echo "========== hahahaha ofs =====" $ofs

 $EXECnos/ofs_variables_values_at_grib2_grid < fields_files_$ofs.in




done


 $EXECnos/ofs_project_back_to_grib2_conus625m




