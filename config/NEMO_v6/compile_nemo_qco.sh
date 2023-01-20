#!/bin/bash
#set -vx
# Default options
#
#
#
date
#### 1  Set up the compiling options
#### Define some directories
submitdir=$( pwd )
modipsl=$submitdir/../..
arch_path=$submitdir/ARCH 
mysrc_path=$submitdir/SOURCES

#### Set default options 
# Coupled with ocean biogeochemistry (y/n)
cpltop=WithTOP
# Coupled with ocean biogeochemistry (y/n)
cplmode=online

# Optimization mode
# optmode=prod/dev/debug
optmode=prod
# fcm_arch
fcm_arch=default
export fcm_arch xios
full_nemo=n
full_xios=""


# Output text file for compilation of each component
datestr=`LC_ALL=C date +"%Y%m%dT%H%M"`
outfile=$submitdir/out_compile_nemo.$datestr
echo > $outfile
echo; echo "Text output from compilation will be stored in file out_compile_nemo.$datestr"; echo 

#### Read arguments 
# Loop over all arguments to modify default set up
while (($# > 0)) ; do
    case $1 in
	"-h") cat <<end_help
########################################################################
# Usage of the script compile_nemo.sh
#
########################################################################

./compile_nemo.sh [Options] 


Options: [ORCA1 / ORCA2 / ORCA025 ] Model resolution, choose only one. Default: ORCA2
         [OFFLINE] Compile Coupled NEMO-TOP in offline mode
         [-full] Full recompilation of all components. This option can be added to all other options.
         [-cleannemo] Full recompilation of NEMO component  only.
         [-debug / -dev / -prod] Level of optimization. One of these can be added to all other compile options. Default: -prod.


Example 1: Default compilation of ORCA_ICE_TOP
./compile_nemo.sh

Example 2: Compilation of TOP offline
./compile_nemo.sh OFFLINE

Example 3: Compilation of ORCA_ICE without passive tracers
./compile_nemo.sh  NOTOP -cleannemo


Example 4: Default resoltuion (LR) compiled in debug mode
./compile_nemo.sh -debug

Example 5: Default compilation with full recompilation of NEMO and XIOS. No clean is needed.
./compile_nemo.sh -full

Example 6: Full recompilation in debug mode
./compile_nemo.sh OFFLINE -debug -full

end_help
exit;;
	"NOTOP")       cpltop=WithoutTOP; shift ;;
	"OFFLINE")     cplmode=offline; shift ;;
	"-arch")       fcm_arch="$2" ; shift ; shift ;;
	"-debug")      optmode=debug ; shift ;;
	"-dev")	       optmode=dev ; shift ;;
	"-prod")       optmode=prod ; shift ;;
	"-full")       full_nemo=y ; full_xios="--full" ; shift ;;
	"-full_xios")  full_xios="--full" ; shift ;;  # Note only full_xios is using double dash: --full
	"-full_nemo")  full_nemo=y ; shift ;;
	"-cleannemo")  full_nemo=y ; shift ;;
	*)	       echo "unknown option "$1" , exiting..." ; exit
    esac
done

echo "Following options are set in current compiling:" >> $outfile
echo "   WithTracer=${cpltop}, coupled_mode=${cplmode}" >> $outfile 
echo "   optmode = $optmode, fcm_arch = $fcm_arch " >> $outfile 
echo "   full_xios=$full_xios, full_nemo=$full_nemo," >> $outfile 
echo >> $outfile

### Read host dependent default values
### These variables will not be changed if they were set as argument
###./host.sh $host
# Later : Following lines should be set in host.sh file
# begin host.sh
if [ $fcm_arch == default ] ; then
    # Find out current host and source specific paths and commands for the host
    case $( hostname -s ) in
	jean-zay*)
	    fcm_arch=X64_JEANZAY;;
	irene170|irene171|irene190|irene191|irene192|irene193)
            fcm_arch=X64_IRENE;;
        irene172|irene173|irene194|irene195)
	    fcm_arch=X64_IRENE-AMD;;
	ciclad*|climserv*)
	    fcm_arch=ifort_CICLAD;;
	*)
	    echo Current host is not known. You must use option -arch to specify which architecuture files to use.
	    echo Exit now.
	    exit
    esac
fi

# Set a link to arch.env if arch-${fcm_arch}.env file exist for current fcm_arch.
# The link arch.env is also set in config.card and will be used by libIGCM to ensure the same running environnement.
if [ -f ARCH/arch-${fcm_arch}.env ] ; then
    echo >> $outfile
    echo "The file ARCH/arch-${fcm_arch}.env will now be sourced with modules needed for compilation for all components"
    echo "Note that this new environement might be kept after compilation." 
    echo "If this is the case, source again your personal environment after compilation. "
    echo " Personal module list before sourcing of ARCH/arch.env file:"    >> $outfile  
    module list   >> $outfile 2>&1 

    # Make a link to this file, to be used also in config.card
    rm -f ARCH/arch.env
    ln -s arch-${fcm_arch}.env ARCH/arch.env

    # Source the file
    source ARCH/arch.env   >> $outfile 2>&1 
    echo >> $outfile 
    echo " New module list after sourcing of ARCH/arch.env file:"    >> $outfile  
    module list   >> $outfile 2>&1 
fi

#### 2 Do the compilation 

## 2.3 Compile xios
cd $modipsl/modeles/XIOS
echo; echo "NOW COMPILE XIOS"
echo >> $outfile ; echo " NOW COMPILE XIOS"   >> $outfile 
echo ./make_xios  --$optmode --arch $fcm_arch --arch_path $arch_path --job 4 $full_xios   >> $outfile 
     ./make_xios  --$optmode --arch $fcm_arch --arch_path $arch_path --job 4 $full_xios   >> $outfile 2>&1
# Test if compiling succeded 
if [[ $? != 0 ]] ; then 
    echo "THERE IS A PROBLEM IN XIOS COMPILATION - STOP"
    exit
fi
# Move executables to modipsl/bin
if [ -f $modipsl/modeles/XIOS/bin/xios_server.exe ] ; then 
    mv $modipsl/modeles/XIOS/bin/xios_server.exe $modipsl/bin/xios_server_${optmode}.exe
else
    echo "THERE IS A PROBLEM IN XIOS COMPILATION EXECUTABLE MISSING - STOP"
    exit
fi


## 2.5 Compile NEMO
nemo_root=$modipsl/modeles/NEMO
cfg_ref=ORCA2_ICE_PISCES
cfg_wrk=ORCA_ICE_TRC
addkeys="key_isf"

if [ ${cplmode} == offline ]  ;  then
   cfg_ref=ORCA2_OFF_TRC 
   cfg_wrk=ORCA_OFF_TRC 
   delkeys="key_si3 key_qco key_isf"
fi
if [ ${cpltop} == WithoutTOP ]  ;  then
   cfg_wrk=ORCA_ICE 
   delkeys="key_top"
fi

echo >> $outfile ; echo cd $nemo_root  >> $outfile
echo >> $outfile ; echo cp $mysrc_path/arch-${fcm_arch}.fcm arch/CNRS/.   >> $outfile
echo >> $outfile

cd $nemo_root ; cp $mysrc_path/arch-${fcm_arch}.fcm arch/CNRS/.

echo >> $outfile
# creation of config
echo >> $outfile ; echo cd $nemo_root  >> $outfile
echo ./makenemo -m ${fcm_arch} -n $cfg_wrk -r $cfg_ref -j0 add_key "$addkeys"  del_key "$delkeys"   >> $outfile
echo >> $outfile
cd $nemo_root
./makenemo -m ${fcm_arch} -n $cfg_wrk -r $cfg_ref -j0  add_key "$addkeys"  del_key "$delkeys"  >> $outfile 2>&1


# Copy of specfic source files
echo >> $outfile ; echo cp $mysrc_path/*.*90  $nemo_root/cfgs/$cfg_wrk/MY_SRC/.   >> $outfile
echo >> $outfile
cp $mysrc_path/*.*90  $nemo_root/cfgs/$cfg_wrk/MY_SRC/.

if [ $full_nemo == y ] ; then
   # To make a full compilation, first make a clean to remove all files produced during previous compilation
   echo ./makenemo -m ${fcm_arch} -n $cfg_wrk -r $cfg_ref clean   >> $outfile
   echo >> $outfile
   ./makenemo -m ${fcm_arch} -n $cfg_wrk -r $cfg_ref clean  >> $outfile 2>&1
fi
echo ./makenemo -m ${fcm_arch} -n $cfg_wrk -r $cfg_ref -j8  >> $outfile
echo >> $outfile
./makenemo -m ${fcm_arch} -n $cfg_wrk -r $cfg_ref -j8  >> $outfile 2>&1


# Test if compiling finished
if [[ $? != 0 ]] ; then
    echo "THERE IS A PROBLEM IN NEMO COMPILATION - STOP"
    exit
fi

echo >> $outfile
echo "Move nemo executable to modipsl/bin" >> $outfile
echo ls -lrt $nemo_root/cfgs/$cfg_wrk/BLD/bin   >> $outfile
ls -lrt $nemo_root/cfgs/$cfg_wrk/BLD/bin  >> $outfile
echo >> $outfile

if [ -f $nemo_root/cfgs/$cfg_wrk/BLD/bin/nemo.exe ] ; then
   mv $nemo_root/cfgs/$cfg_wrk/BLD/bin/nemo.exe $modipsl/bin/opa_${cplmode}_${optmode}.exe
else
    echo "ERROR gcm${suffix} executable does not exist."
    echo "THERE IS A PROBLEM IN NEMO COMPILATION - STOP"
    exit
fi


echo >>$outfile ; echo "ALL COMPILING FINISHED" >> $outfile
echo ls -lrt modipsl/bin >> $outfile
ls -lrt $modipsl/bin >> $outfile

echo; echo "ALL COMPILING FINISHED" ; echo
echo "Executables are found in modipsl/bin"
echo "Check that executable names correspond with the name set in config.card before launching the job"
echo ls -lrt modipsl/bin
ls -lrt $modipsl/bin

date

exit


