RBI 20210715

Install required Perl modules if not available yet from CPAN or with package
manager (apt on Ubuntu yum on Centos, for example)

Getopt::Long
IO::Uncompress::Bunzip2
Log::Log4perl
IPC::Run
Date::Calc

$ cd demo


Example if JSON input:
{
    "_comment": "This is the input file to extract time series from grid ens files",
    "sq": "0251",
    "cs": "001",
    "rl": "67",
    "vr": "01",
    "extract_utc": 1,
    "models": [
        10701
    ],
    "statistics": {
      "01": {},
      "02": {
        "time_masks_dir": "../../aqmeii4_generated_data/NA2016/GAS_AEROSOL/PM10/D",
        "operator": "AVG"
      },
      "03": {
        "time_mask": "./time_masks/mask.2016.monthly.csv",
        "operator": "AVG"
      },
      "04": {
        "time_mask": "./time_masks/mask.2016.period.csv",
        "operator": "AVG"
      },
      "05": {
        "time_mask": "./time_masks/mask.2016.hourly.csv",
        "operator": "AVG"
      }
    },
    "pool_file": "pool_files/na2016_pm10.csv",
    "create_dirs": 1,
    "vrmax": 4,
    "home_dir": {
        "src": "./src_files",
        "bz2": "./bz2_files",
        "ens": "./ens_files",
        "dat": "./dat_files",
        "out": "./out_files",
        "json": "./json_files"
    },
    "executables": {
        "deform": "./bin/deform_aq"
    },
    "go" : {
        "bunzip2": 0,
        "deform": 0,
        "extract": 1
    }
}

Edit rec_extractor.json as necessary (set go_ parameters to 1 to execute
action):
    "go" : {
        "bunzip2": 0,    <--- to execute bunzip2 on bz2 files
        "deform": 0,     <--- to decode the ens files to get the dat files
        "extract": 1     <--- to extract the time series
    

** pool_file

The pool file contains a list of sites with coordinates and delta from UTC
(positive Eastward)

LNAME,LAT,LON,DUTC
AIRSUSAZ1APJ,33.42119,-111.50322,-7.0
AIRSUSAZDPHO,33.48385,-112.14257,-7.

When the time mask (see below) is specified for each station by using the input keyword time_masks_dir, 
only site names in the pool file that match the site name in one of the files within the time_masks_dir
will be processed.

** time_mask

This is an ASCII file with one or more arbitrary intervals that specify the
first and the last hour of the day (01 is first hour, wall clock time from
00:00 to 01:00) that is included in the time averaging of hourly data extracted.
You can see these files in the demo/time_masks folder.
For example, the first records of the  demo/time_masks/mask.2016.daily.csv file 
that is used to compue the daily averages are:
2016010101,2016010200
2016010201,2016010300
2016010301,2016010400
2016010401,2016010500
2016010501,2016010600

These time masks allow to define arbityary periods, so with the proper mask it 
is possible to average (or any other operator we want to implement) the hourly 
data in any desired time interval.

The time mask is applied to produce any non-hourly average implemented in this
software. Using it for v01 gives an error.

** time_masks_dir

It is also possible to apply a time_mask that is different for each site. Such
time_mask files must be placed in the time_masks_dir specified in input. 
For each time mask file named somefilename.tm there must be a corresponding
somefilename.info, made of two records:
LCODE,LNAME,NETWORK,LAT,LON,ELEVATION,CCODE,SCODE,SITE_LAND_USE_1,SITE_LAND_USE_2,IS_UTC,DUTC,UNITS,MISSING,START_TIME,TIME_UNITS,DELTA_TIME_UNITS,NT,VALID_PERCENT,COMMENT,FILE
AIRSUSAZ1APJ,APACHE JUNCTION FIRE STATION,AIRS,33.42119,-111.50322,550,US,AZ,Suburban,Residential,0,-7.0,,-9,2016010100,D,1,365,92.329,,PM10_D_AIRSUSAZ1APJ.csv

The program will read the .info files in the folder and will use the
time_mask specific to each site, based on LCODE

** operator
This is the operator applied to the extracted model data. Currently implemented:
AVG --> average of model values within time window 
INT --> sum of model values within time window 
SKIP --> when applied to the vr variable (e.g. 01), it suppresses the creation of
         of the file with the data extracted from the model
         

** extract_utc
If"extract_utc: 1" the time shift from UTC to LST won't be made.
It can be used to extract time series that are going to be compared with measuerements in UTC. 
A sample JSON  is demo/rec_extractor.json. Default is to apply time shift.


To run some examples:

$ cd demo
$ perl ../rec_extractor.pl -jsonfile=rec_extractor_lst.json
$ perl ../rec_extractor.pl -jsonfile=rec_extractor_utc.json

