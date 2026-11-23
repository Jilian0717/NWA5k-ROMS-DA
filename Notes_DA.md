
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
  - data:
  - code:
  - assigned innitial obs_error = 1˚C

- SLA 
  - data:
  - code:
  - ROMS 10-year (2014-2023) free run mean SSH, zeta_mean_2014_2024_0001_0118.nc
  - assigned initial obs_error = 6 cm
  - reconstructed tide:
    - directory: 

- Oleander ADCP
  - data:
  - code
  - assigned initial obs_error = cm/s
  - notes: the downloaded ADCP u and v is 5-min frequency and has already passed QC but it worth a double check

#### Merge observation

#### Create super obs

#### adjust observation error



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

  Input file: `roms_avg_mean_TS_zeta_0001_0118.nc`. Mean temperature, salinity, and zeta based on roms_avg_0001.nc to roms_avg_0118.nc in `/proj/argon/jxiong/Grid_5km/NWA5k12_t1424_nesh3/`

  Output file: `rosbby_radius_10yr_mean.nc`

- run `02_create_deccorrelation_length_scale_double.py`

  Inpute file: `rosbby_radius_10yr_mean.nc`

  Output file: `NWA5k_Bcorr_xy_double.nc`


### Configure Normalization run:

- Set up the CPP flags in `build_roms.sh`, following the [WC13 examples](https://github.com/myroms/roms_test/tree/main/WC13/Normalization) 
- Build the executable `romsM`: ./build_roms.sh
- Configure the Normalization Input files:

    `c4dvar_NWA5k12.in` 

    LdefNRM == T F F F F

    LwrtNRM == T F F F F

    CnormI(*) = T

    Nmethod = 1 # approximated, faster than the "exact" method for large domain

    VdecayI = 30 # vertical decorrelaiton length scale = 30m

    SVCname = NWA5k_Bcorr_xy_double.nc

    STDnameI, STDnameB, STDnameF: these files are not really used in Normalization run but the Normalization run requires them

    NRMnameI: the output file name

    `roms_nes.in`

    APARNAME = c4dvar_NWA5k12.in

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




Issues:
f2023.10.28 blows up after adding ADCP data; I suspect the observation file has some problem. An intial check doesn't reveal outliers.

ovsn nodes may become "drain" (i.e. unavailable)


Debugging: ROMS 4D-Var Crash Due to Long obs_provenance:flag_meanings

Problem

ROMS RBL4DVAR crashed during nonlinear model initialization with an incorrect forcing-time interpolation:

SET_NGFLD - current model time exceeds ending value
            for variable: river_transport
TDAYS   =   44925.0000
TINTRP1 =   44908.0000
TINTRP2 = -692501.0000

River, boundary, and atmospheric forcing times became incorrect, even though the forcing files and model configuration were unchanged.

Debugging

Two observation NetCDF files were compared:

* Code 1: Original CrocoLake observations — ROMS runs successfully.
* Code 2: Updated observations with revised provenance metadata — ROMS crashes.

The observation arrays were identical except for obs_variance, which was independently ruled out.

Controlled tests showed:

Test	Result
Original Code 1	PASS
Updated Code 2	FAIL
Code 1 + Code 2 global obs_provenance	PASS
Code 1 + Code 2 variable flag_meanings	FAIL
Code 1 + shortened variable flag_meanings	PASS
Changing obs_Zgrid, obs_variance, or flag_values dtype	Did not resolve the error

Root Cause: Potential Fortran Buffer Overflow

In ROMS/Utility/def_mod.F, ROMS reads the attributes of the obs_provenance variable through:

CALL netcdf_inq_var (ng, iNLM, OBS(ng)%name,  &
     &               ncid = OBSncid,         &
     &               MyVarName = TRIM(Vname(1,idOpro)), &
     &               nVarDim = nvdim,        &
     &               nVarAtt = nvatt)

In ROMS/Modules/mod_netcdf.F, netcdf_inq_var declares:

character (len=1024) :: text

However, the attribute is read without checking its length against the buffer:

status=nf90_get_att(my_ncid, my_id, &
     &              TRIM(var_Aname(i)), &
     &              text(1:my_Alen))

If my_Alen > 1024, the substring exceeds the declared buffer, potentially causing undefined behavior and corrupting subsequent model initialization.

Observed attribute lengths:

Observation file	flag_meanings length	Result
Code 1	1327 bytes	PASS
Code 2	1775 bytes	FAIL
Revised short names	879 bytes	Pending final DA test

Note that Code 1 also exceeds 1024 characters but runs successfully, consistent with the possibility of undefined behavior. The exact mechanism linking the attribute overrun to the forcing-time error has not been directly verified.

Solution / Workaround

Shorten provenance names while preserving their numeric IDs.

For example:

"CORA_Vertical_profiles_from_conductivity-temperature-depth_instrument_observations_pt"

becomes:

"CORA_Vertical_profiles_CTD_pt"

Add a validation check before writing the observation NetCDF:

flag_meanings = " ".join(OBS_PROVENANCE_FLAGS_short.values())
assert len(flag_meanings.encode("utf-8")) < 1024
ds["obs_provenance"].attrs["flag_meanings"] = flag_meanings
ds.attrs["obs_provenance"] = flag_meanings

Important: ROMS also uses a 2048-character buffer for the global obs_provenance attribute in def_mod.F. Both limits should be respected.

Takeaway: Long NetCDF character attributes can potentially trigger memory-related errors in ROMS, even when observation values and forcing files are valid. Validate metadata lengths during observation preprocessing.
