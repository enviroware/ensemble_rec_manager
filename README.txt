Install required Perl modules if not available yet from CPAN or with package
manager (apt on Ubuntu yum on Centos, for example)

Getopt::Long
IO::Uncompress::Bunzip2
Log::Log4perl
IPC::Run
Date::Calc

$ cd demo

Edit rec_extractor_lst.json as necessary (set go_ parameters to 1 to execute
action):
    "go" : {
        "bunzip2": 0,    <--- to execute bunzip2 on bz2 files
        "deform": 0,     <--- to decode the ens files to get the dat files
        "extract": 1     <--- to extract the time series
    
The pool file has the list of sites with coordinates and delta from UTC
(positive Eastward)

Run the code 
$ perl ../rec_extractor_lst.pl -jsonfile=rec_extractor_lst.json


