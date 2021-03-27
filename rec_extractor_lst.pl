use strict;

# Author: rbianconi@enviroware.com

my $VERSION = '20210321';

if ($^O eq 'MSWin32') {
    print "This code must be run under Linux or macOS\n";
    exit();
}
use FindBin;
use lib $FindBin::Bin;

use Library qw(
    init_input
    check_input
    extract_values_from_grid
    set_info
    load_sq_json_file
    load_receptors
    node
);
use Getopt::Long;
use Data::Dumper;
use File::Basename;
use File::Path;
use IO::Uncompress::Bunzip2 qw(bunzip2 $Bunzip2Error) ;
use Log::Log4perl qw(:easy);
use POSIX qw (strftime floor);
use IPC::Run qw( run );
use Date::Calc qw( Add_Delta_DHMS );

Log::Log4perl->easy_init($INFO);
my $logger = Log::Log4perl->get_logger();

# Read user input from JSON file and load defaults

my $show_help_info = '';
my $ret = init_input();
my @input_list = @{$ret->{input_list}};
my $hinput = $ret->{input};

GetOptions(@input_list,'help'=>\$show_help_info);

my $ret = check_input(Input=>$hinput,Logger=>$logger);
my $hinfo = $ret->{info};
$hinput = $ret->{input};

$ret = set_info(Info=>$hinfo,Input=>$hinput,Logger=>$logger);
$hinfo = $ret->{info};

my %input = %{$hinput};
my %info = %{$hinfo};

my $sq = $input{sq};
my $cs = $input{cs};
my $rl = $input{rl};
my $vr = $input{vr};

# Load sequence info
my %sq_json = load_sq_json_file(File=>"$input{home_dir}{json}/$sq.json");
my $date = $sq_json{cases}{"c$cs"}{first_output};
my @start_date = unpack("a4a2a2a2a2",$sq_json{cases}{"c$cs"}{start});
my $missing = $sq_json{cases}{"c$cs"}{releases}{"r$rl"}{variables}{"v$vr"}{missing_value};
my $src_file = "$input{home_dir}{src}/$sq-$cs.src";

# Loop on models
my @models = @{$input{models}};
foreach my $mo (@models) {

    my $base = "$mo-$sq-$cs-$rl-$vr-$date";
    my $vbase = "v$vr-$mo-$sq-$cs-$rl-$date";
    my $bz2_file = "$input{home_dir}{bz2}/$mo/$sq/$cs/$base.ens.bz2";
    my $ens_file = "$input{home_dir}{ens}/s$sq/c$cs/$base.ens";
    my $dat_file = "$input{home_dir}{dat}/s$sq/c$cs/r$rl/v$vr/$vbase.dat";
    my $out_folder = "$input{home_dir}{out}/$sq/$cs/$rl/$vr/$mo";
    my $dat_log_file = "$input{home_dir}{dat}/s$sq/c$cs/$base.log";

    # Uncompress ens.bz2 grid file (optional)
    if ($input{go}{bunzip2}) {
        die "$bz2_file: $!" unless (-e $bz2_file);
        my ($basename,$path,$suffix) = fileparse($ens_file,'.ens');
        if ($input{create_dirs}) {
            mkpath $path unless (-e $path);
        }
        my $status = bunzip2 $bz2_file => $ens_file or die "bunzip2 failed: $Bunzip2Error\n";
    }

    # Decode ens grid file (optional)
    if ($input{go}{deform}) {
        #  1,INPUT_PATH
        #  2,INPUT_FILE
        #  3,SOURCE_FILE
        #  4,MODEL_NAME
        #  5,UPL_DATE
        #  6,DELTA_M
        #  7,DELTA_U
        #  8,UPL_USER
        #  9,UPL_IP
        # 10,OUTPUT_BASE_PATH
        my $now = strftime("%Y%m%d%H%M", localtime(time));

        my $status_c_folder = "$input{home_dir}{dat}/s$sq/c$cs/status_c";
        mkpath $status_c_folder unless (-e $status_c_folder);
        my $status_r_folder = "$input{home_dir}{dat}/s$sq/c$cs/r$rl/status_r";
        mkpath $status_r_folder unless (-e $status_r_folder);
        for my $iv (1..$input{vrmax}) {
            my $vro =  sprintf "%2.2d", $iv;
            my $dat_folder = "$input{home_dir}{dat}/s$sq/c$cs/r$rl/v$vro";
            mkpath $dat_folder unless (-e $dat_folder);
        }
        my @command = (
            $input{executables}{deform},
            "$input{home_dir}{ens}/s$sq/c$cs/",
            $base.'.ens',
            $src_file,'DUMMY',$now,'+0m','+0m','dummy','127.0.0.1',
            "$input{home_dir}{dat}/"
        );

        my $cmd = join (" ",@command);
        run "$cmd > $dat_log_file 2>&1";

    }

    # Extract UTC from receptors
    if ($input{go}{extract}) {

        mkpath $out_folder unless (-e $out_folder);

        my $precision = $sq_json{cases}{"c$cs"}{releases}{"r$rl"}{variables}{"v$vr"}{precision};

        my $decimals = - log($precision) / log(10);
        # Generate output_dates
#       my @datetimes = generate_datetimes(Start=$sq_json{first_output_utc});

        # Load pool of receptors
        my %receptors = load_receptors(File=>$input{pool_file});

        my @ts = (1..$sq_json{nt});

        # Loop on receptors
        foreach my $lcode (sort keys %receptors) {
            my @xs = (node(Value=>$receptors{$lcode}{lon},GridSize=>$sq_json{dx}));
            my @ys = (node(Value=>$receptors{$lcode}{lat},GridSize=>$sq_json{dy}));
            my $dutc = $receptors{$lcode}{dutc};
            die "DUTC not integer ($dutc) for $lcode" if (floor($dutc) < $dutc);

            my $fdate_lst = sprintf "%.4d-%.2d-%.2d".'T'."%.2d:%.2d:00", @start_date[0..4];

            my @values = extract_values_from_grid(
                            DatFile =>$dat_file,
                            Xs => \@xs,
                            Ys => \@ys,
                            Ts => \@ts,
                            Domain => \%sq_json);
            my $out_file = "$out_folder/$lcode-$mo-$sq-$cs-$rl-$vr.csv";
            open(OUT,">$out_file") or die "$out_file:$!";
            foreach my $it_lst (@ts) {

                # Apply time shift to time series

                my @t_date_lst = Add_Delta_DHMS(@start_date,0,
                                              0,0,$it_lst*$sq_json{dt_out},0);
                my $tdate_lst = sprintf "%.4d-%.2d-%.2d".'T'."%.2d:%.2d:00", @t_date_lst[0..4];

                my $idx_utc = $it_lst - $dutc + 1;
                my $valp = ($idx_utc < 0 or $idx_utc > $#ts) ? $missing : $values[$idx_utc];
                my $valpout = sprintf "%.${decimals}f", $valp;
                print OUT "$valpout,$fdate_lst,$tdate_lst\n";
                print "$valpout,$fdate_lst,$tdate_lst\n";

                $fdate_lst = $tdate_lst;
            }

            # Save time series 
            close (OUT);

        }


# Apply optional time averaging and save time series

# Delete dat grid file (optional)
    }
}

