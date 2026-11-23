
Tutorial: https://www.myroms.org/wiki/4DVar_Tutorial_Introduction

## 1. Observation file
- create a python env that has matlab enginee
- `obs_depth` store the physical observation depth in meter (negative downward), while `obs_Zgrid` stores the fractional z grid. ROMS DA will [update](https://www.myroms.org/projects/src/ticket/895) obs_Zgrid internally. However, super_obs.m requires valid obs_Zgrid to vertically bin observations. Therefore, obs_Zgrid cannot be innitalized to zero if using super obs.
- `obs_variance` is very likely not used in DA. I included it for completeness, following the WC13 example (wc13_obs.nc)
- ROMS observation NetCDF files have length limitations on `obs_provenance` metadata. Exceeding these limits may cause DA runs to crash with unexpected errors, such as incorrect forcing-time interpolation.
    * Global attribute (< 2048 characters): In ROMS/Utility/def_mod.F, ROMS reads ds.attrs['obs_provenance'] into a fixed-length Fortran character array: character (len=2048) :: AttValue(2).
    * Variable attribute (< 1024 characters): In ROMS/Modules/mod_netcdf.F, ROMS reads ds['obs_provenance'].attrs['flag_meanings'] using character (len=1024) :: text, without checking whether the attribute exceeds the buffer length.
    * In my observation files, these two attributes contain the same provenance descriptions. The DA crash was traced to an overly long variable attribute (flag_meanings) through controlled tests.
    * Solution: Shorten the provenance names! 
  

#### create obs file from each data source
- CrocoLake (reserve OleanderXBT and 20% argo profiles for 2023)
  - code:
  - innitial obs_error = provided value from crocoLake or 0.002 ˚C or 0.01 psu for missing values

- CrocoLake (no reservation)
  - code:
  - innitial obs_error = provided value from crocoLake or 0.002 ˚C or 0.01 psu for missing values

- non-CrocoLake TS profiles by Yu
  - code:
  - assigned initial obs_error = 0.002 ˚C, 0.01 psu

- SST
  - link: https://coastwatch.noaa.gov/cwn/products/noaa-geo-polar-blended-global-sea-surface-temperature-analysis-level-4.html
  - data:
  - code:
  - assigned innitial obs_error = 1˚C

- SLA
  - link: https://data.marine.copernicus.eu/product/SEALEVEL_GLO_PHY_L4_MY_008_047/description
  - data: 
  - code:
  - ROMS 10-year (2014-2023) free run mean SSH, zeta_mean_2014_2024_0001_0118.nc
  - assigned initial obs_error = 6 cm
  - reconstructed tide using a free run that only saves hourly zeta
    - directory: /proj/argon/jxiong/Grid_5km/NWA5k12_t1424_nesh3_hourly_zeta/

- Oleander ADCP
  - link: https://currents.soest.hawaii.edu/oleander/flastik/index.html
  - data: 
  - code:
  - assigned initial obs_error = cm/s
  - notes: the tested ADCP u and v for 2023.09-12 is 5-min frequency and has already passed QC but it worth a double check

#### Merge observations
  - run d01_merge.py to merge observations; will call the matlab function obs_merge
  - set dt = 5min to merge obs within a 5-min time window

#### Create super obs
  - run d02_create_super_obs.py; will call the matlab function super_obs

#### adjust observation error
   - run d03_modify_super_obs_error_tuneRV1.4.py


## 2. ROMS 4DVar Normalization Run
### Tutorial:
https://www.myroms.org/projects/src/ticket/988

https://github.com/myroms/roms_test/blob/main/WC13/Normalization/Readme.md

https://github.com/myroms/roms/wiki/ROMS-4DVAR-Data-Assimilation#background-error-covariance-modeling


### Create decorrelation length scale file:

#### Directory: 
`/proj/ovsn/jxiong/DA/Normalization_spatial_varying_double/decorrelation_length_scale/` 

#### Steps:
- run `01_calculate_rossby_radius.py`

  * Input file: `roms_avg_mean_TS_zeta_0001_0118.nc`. Mean temperature, salinity, and zeta based on roms_avg_0001.nc to roms_avg_0118.nc in `/proj/argon/jxiong/Grid_5km/NWA5k12_t1424_nesh3/`

  * Output file: `rosbby_radius_10yr_mean.nc`

- run `02_create_deccorrelation_length_scale_double.py`

  * Inpute file: `rosbby_radius_10yr_mean.nc`

  * Output file: `NWA5k_Bcorr_xy_double.nc`


### Configure Normalization run:

- Set up the CPP flags in `build_roms.sh`, following the [WC13 examples](https://github.com/myroms/roms_test/tree/main/WC13/Normalization) 
- Build the executable `romsM`: ./build_roms.sh
- Configure the Normalization Input files:

    `c4dvar_NWA5k12.in` 

    * LdefNRM == T F F F F
    * LwrtNRM == T F F F F
    * CnormI(*) = T
    * Nmethod = 1 # approximated, faster than the "exact" method for large domain
    * VdecayI = 30 # vertical decorrelaiton length scale = 30m
    * SVCname = NWA5k_Bcorr_xy_double.nc
    * STDnameI, STDnameB, STDnameF: these files are not really used in Normalization run but the Normalization run requires them
    * NRMnameI: the output file name
      
    `roms_nes.in`
    * APARNAME = c4dvar_NWA5k12.in

- Submit the job: sbatch run.sh


## 3. Prepare model standard deviation (std) file for initial condition

- **Free run model:** 2014-2024 `/proj/argon/jxiong/Grid_5km/NWA5k12_t1424_nesh3/`
- **Working directory:** `/proj/ovsn/jxiong/DA/DATA/roms_matlab/4dvar/`

#### Step 1: Generate the raw monthly std files

- Run the MATLAB script `d_std.m` on hydra.
- Output is one NetCDF file per month, 12 in total:
  `NWA5k12_std_i_correct_river_jan.nc`, `NWA5k12_std_i_correct_river_feb.nc`, …

#### Step 2: Adjust the std iteratively based on Desroziers analysis

- Start from the monthly NetCDF file saved in step 1
- Each round is saved in its own folder: `./modify_std_v1.0/`, `./modify_std_v1.1/`, `./modify_std_v1.2/`, …
- Each round builds on the previous one:
  `modify_std_v1.N = modify_std_v1.(N-1) * factors`
  (e.g. the NetCDF files in `v1.1` are the files in `v1.0` multiplied by factors)
- The factors used in each round are recorded in `00_modify_std.sh` inside that round's folder.

#### Step 3: Final version

- The NetCDF files in `./modify_std_v1.4/` are the final std used in the DA system.

## 4. Run DA, 2023
#### Directory: 
`/proj/ovsn/jxiong/DA/RBL4DVAR/NOAA_CoastWatch_GEO_Polar_L4fndSST_20230101/crocV1.1_VL2_tuneBR_v1.4_Nouter1_Ninner20`

#### Input: 
- Super observations
   - upload super observation files to './super_obs/'
   - ./move_files.sh: move each super observation files to each folders: f2023.01.01, f2023.01.04...
   - ./create_solft_link.sh: link each super observation files to a standard name 'obs_super.nc' for the convenience of the following script
- roms_nes_blank.in
   - set NtileI, NtileJ to the same as run_blank.sh
   - Nouter = 1; Ninner = 21 # 20 inner loops, but +1 is required for [RPCG](https://github.com/myroms/roms_test/blob/main/WC13/RBL4DVAR/Exercise_3.pdf)
   - APARNAME = out_dir/rbl4dvar.in
- rbl4dvar_blank.in

   - STDnameI # only adjust initial condition
   - NRMnameM and NRMnameI # normalization file

- run_blank.sh
   - set node configuration and jobname
     
- ocean_ini_20230101_add_vars.nc
    
    - Initial file used for the 1st DA window
    - Python scripts used to create this file are in `/proj/argon/jxiong/Grid_5km/forcings/ocn12`
 
      - gen_ini_file.py
      - add_more_var_2_ini_for_DA_Hydra.py

#### Run DA 
`driver_VL2_tuneBR_O1I20.py`: automatically launch every 3-day window
- ds0 = '2023.01.01'  # start time; adjust this if DA runs from mid of the 2023.
- ds1 = '2023.12.31'  # end time; adjust this if necessary
- start_type = 'new' or 'continuation': when ds0 = '2023.01.01' set start_type = 'new', otherwise start_type = 'continuation'
- jobname: choose a unique job name; the driver code will decide if a 3-day DA run is still working or has finished based on this jobname.
- call `make_dot_in.py`:
    
     - read 'roms_nes_blank.in' and create 'roms_nes.in'; read 'rbl4dvar_blank.in' and create 'rbl4dvar.in'
     - if DA starts at 2023.01.01, ininame = `ocean_ini_20230101_add_vars.nc`; else ininame = `roms_dia_0.nc`, adjusted initial condition from previous window.
     - dir_std = `/proj/ovsn/jxiong/DA/DATA/roms_matlab/4dvar/modify_std_v1.4/` # this is the model standard deviation after after several round of Desroziers adjustment
     - std_str = `NWA5k12_std_i_correct_river_Btuned_`
     - output file: roms_nes.in, rbl4dvar.in

     
- call `make_batch_in.py`:

    - read 'run_blank.sh' and create run.sh. The jobname in 'run_blank.py' should be the same as jobname in the driver code
    
- On hydra login node, run "python driver_VL2_tuneBR_O1I20.py > tmp &"



#### Known issues:
- DA run blows up on f2023.10.28: the run crashes after adding ADCP data. I suspect an issue with the observation file, although an initial check did not reveal obvious outliers. 
- ovsn nodes may become "drain", making them temproraily unavailable for running jobs.
