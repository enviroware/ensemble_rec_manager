package Library;

# Author: R.Bianconi - Enviroware srl

use strict;
require Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw(
    anytrim
    check_input
    compute_statistics
    extract_values_from_grid
    get_files
    init_input
    load_sq_json_file
    load_receptors
    load_statistics
    node
    set_info

);
our @EXPORT_OK = qw();
my $VERSION = '20211116'; # Store operator for variable 01
# my $VERSION = '20210715';   
#my $VERSION = '20210622'; # Added time_masks at lcode level
#my $VERSION = '20210526'; # Added statistics
#my $VERSION = '20210407'; # CHO fix to _variable_node_index

use Data::Dumper;
use Tie::File;
use FileHandle;
use File::Basename;
use JSON;
use Date::Calc qw (Delta_DHMS Add_Delta_DHMS Delta_YMDHMS Add_Delta_YMDHMS);
use File::Path;
use POSIX qw(floor);
use FindBin qw ($Bin);

#-----------------------------------------------------------------------------#

sub load_sq_json_file {

    my %args = @_;

    my $sq_json_file = $args{File};
    my %sq_json = %{read_json_file(File=>$sq_json_file)};   
    return %sq_json;

}

#-----------------------------------------------------------------------------#

sub load_statistics {

    my %args = @_;
    my $hinput = $args{Input};

    my %statistics_in = %{$hinput->{statistics}};

    my %statistics;
    my @keys = qw(time_mask_from time_mask_to);
    my @ids = sort keys %statistics_in;

    foreach my $id (@ids) {

        $statistics{$id}{operator} = $statistics_in{$id}{operator};
        # Skip var=01 because they are hourly values - but store operator
        # because it may be SKIP
        next if ($id eq '01');

        if (exists($statistics_in{$id}{time_mask})) {
            $statistics{$id}{is_any} = 1;
            $statistics{$id}{time_mask} = $statistics_in{$id}{time_mask};
            # Read time_mask file
            my $mask_file = $statistics_in{$id}{time_mask};
            open(MSK,"<$mask_file") or die "$mask_file: $!";
            my @lines = <MSK>;
            close(MSK);
            my %stat = parse_time_mask(Lines=>\@lines);
            map { $statistics{$id}{any}{$_} = $stat{$_} } (@keys);
        } elsif (exists($statistics_in{$id}{time_masks_dir})) {
            $statistics{$id}{is_any} = 0;
            # Read time_mask files (one for each station in pool file
            my @mask_files = get_files(Dir=>$statistics_in{$id}{time_masks_dir},Filter=>'\.tm');
            foreach my $mask_file (@mask_files) {
                my ($name,$path,$suffix) = fileparse($mask_file,'.tm');
                my $info_file = "$statistics_in{$id}{time_masks_dir}/$name.info";
                open(INFO,"<$info_file") or die "$info_file: $!";
                my @ilines = <INFO>;
                close(INFO);
                my @fields = split(",",$ilines[1]);
                my $lcode = $fields[0];
                my $mfile = "$statistics_in{$id}{time_masks_dir}/$name.tm";
                open(MSK,"<$mfile") or die "$mfile: $!";
                my @lines = <MSK>;
                close(MSK);
                my %stat = parse_time_mask(Lines=>\@lines);
                map { $statistics{$id}{each}{$lcode}{$_} = $stat{$_} } (@keys);
            }
        }else {
            die "Please specify either time_masks_dir or time_mask for $id";
        }
    }

    return %statistics;

}

#-----------------------------------------------------------------------------#

sub parse_time_mask {

    my %args = @_;

    my @lines = @{$args{Lines}};

    my %stat;

    # Loop from first datetime_from to last datetime_to
    # in time_mask file
    while (@lines) {
        my $line = shift @lines;
        chomp $line;
        my ($from,$to) = split(",",$line);
        my @from_in = unpack("a4a2a2a2",$from);
        my @to_in = unpack("a4a2a2a2",$to);
        # Hours in interval after first one (ie 23 for a full day of 24)
        my ($Dd,$Dh,$Dm,$Ds) =
            Delta_DHMS(@from_in,0,0, @to_in,0,0);
        my $nh = $Dd * 24 + $Dh;

        # Assign each hour within interval to the 
        # corresponding averaging period.
        # There can be holes:
        # for example only week 12 and week 33 of the year
                     
        $stat{time_mask_from}{$from} = $from;
        $stat{time_mask_to}{$from} = $to;

        for my $ih (1..$nh) {
            my ($Dy,$Dmo,$Dd,$Dh,$Dm,$Ds) =
                Add_Delta_YMDHMS(@from_in,0,0, 0,0,0,$ih,0,0);
            my $dt = sprintf "%.4d%.2d%.2d%.2d", $Dy,$Dmo,$Dd,$Dh;
            $stat{time_mask_from}{$dt} = $from; 
            $stat{time_mask_to}{$dt} = $to; 
        }
    }

    return %stat;

}

#-----------------------------------------------------------------------------#

sub load_receptors {

    my %args = @_;

    my $file = $args{File};
    my $hinfo = $args{Info};

    tie my @array, 'Tie::File', $file, mode => O_RDONLY;
    my @headers = anytrim (split(/\,/, $array[0]));
    my %index;
    @index{@headers} = (0..$#headers);

    my $idx_lcode = $index{LCODE};
    my $idx_lon = $index{LON};
    my $idx_lat = $index{LAT};
    my $idx_dutc = $index{DUTC};

    my $x_min = $hinfo->{x_min};
    my $y_min = $hinfo->{y_min};
    my $x_max = $hinfo->{x_max};
    my $y_max = $hinfo->{y_max};

    my %receptors;

    foreach my $ii (1..$#array) {

        my @parts = anytrim (split(/\,/, $array[$ii]));

        my $lcode = $parts[$idx_lcode];
        my $lon = $parts[$idx_lon];
        my $lat = $parts[$idx_lat];

        if (($lon < $x_min) || ($lon > $x_max) || ($lat < $y_min) || ($lat > $y_max)) {
            die "Please check coordinates of receptor $lcode (record $ii of pool file $file).\n".
                " (($lon < $x_min) || ($lon > $x_max) || ($lat < $y_min) || ($lat > $y_max)) \n";
        }

        $receptors{$lcode}{lon} = $lon;
        $receptors{$lcode}{lat} = $lat;
        $receptors{$lcode}{dutc} = $parts[$idx_dutc];

    }

    return %receptors;
    
}

#-----------------------------------------------------------------------------#

sub anytrim {

    my @array;
    for ( @_ ) {
        if ( ref ) {
            push @array,
                ref eq 'ARRAY'  ? [ anytrim( @$_ ) ] :
                ref eq 'HASH'   ? { anytrim( %$_ ) } :
                ref eq 'SCALAR' ?  \anytrim( $$_ ) :
                ();
                }
        else {
            if (defined($_)) {
                ( my $var = $_ ) =~ s/^\s+//;
                $var =~ s/\s+$//;
                push @array, $var;
                }
            }
        }
    return wantarray ? @array : $array[ 0 ];
}

#--------------------------------------------------------------------#

sub check_input {
    
    my %args = @_;
    my $hinfo = $args{Info} || {};
    my $hinput = $args{Input} || {};

    my %info = %{$hinfo};
    my %input = %{$hinput};

    _print_info(Input=>$hinput);

    my $jinp = $input{jsonfile};
    if ($input{jsonfile}) {
        die whoami()." The specified JSON input file ($input{jsonfile}) does not exist." unless (-e $input{jsonfile});
        %input = %{read_json_file(File=>$input{jsonfile})};
    } else {
        die "Please provide a JSON file (-jsonfile=/path/to/input.json).\n";
    }
    $input{jsonfile} = $jinp; 

    my $ret = {
        info => $hinfo,
        input => \%input
    };

    return $ret;

}

#------------------------------------------------------------------------------#

sub compute_statistics {

    my %args = @_;

    my $operator = $args{Operator};
    my @values = @{$args{Values}};
    my $missing = $args{Missing};
    my $result;
    if (uc($operator) eq 'AVG') {

        my $tot = 0;
        my $count = 0;
        foreach my $vv (@values) {
            unless  ($vv == $missing) {
                $tot = $tot + $vv;
                $count++;
            }
        }
        $result = ($count > 0) ? $tot/$count : $missing;

    } elsif (uc($operator) eq 'INT') {

        my $tot = 0;
        my $count = 0;
        foreach my $vv (@values) {
            unless  ($vv == $missing) {
                $tot = $tot + $vv;
                $count++;
            }
        }
        $result = ($count > 0) ? $tot : $missing;
    
    } else {
        die "$operator not implemented.";
    }

    return $result;

}

#------------------------------------------------------------------------------#

sub extract_values_from_grid {

    my %args = @_;

    my $dat_file = $args{DatFile};
    my @xs = @{$args{Xs}};
    my @ys = @{$args{Ys}};
    my @ts = @{$args{Ts}};
    die "Ts must be positive" unless ($ts[0] > 0);
    my %domain = %{$args{Domain}};

    my $datasize = 14;  # ENSEMBLE AQ (V5)
    my $bt = 14 * $domain{nx} + 1;
    open FHH, "<$dat_file" or die "$dat_file: $!";

    my @values;
    foreach my $t (@ts) {
        foreach my $y (@ys) {
            foreach my $x (@xs) {
                my $start = _variable_node_index(
                    X=>$x,Y=>$y,T=>$t,
                    DxDomain=>$domain{dx},
                    DyDomain=>$domain{dy},
                    NxDomain=>$domain{nx},
                    NyDomain=>$domain{ny},
                    BytesLine=>$bt,
                    XminDomain=>$domain{x_min},
                    YmaxDomain=>$domain{y_max},
                    IsAirQuality=>1,
                );
                my $value;
                seek(FHH,$start,0);
                read(FHH,$value,$datasize);
                push @values, $value*1.;
            }
        }
    }
    close FHH;

    return @values;

}

#------------------------------------------------------------------------------#

sub init_input {

    my @numerics = qw();

    my @flags = qw(
        jsonfile
    );

    my @input_list;
    my %input;

    map {
        push @input_list, "$_=i" => \$input{$_};
    } (@numerics);
    map {
        push @input_list, "$_=s" => \$input{$_};
    } (@flags);

    my $ret = {
        input_list => \@input_list,
        input => \%input
    };

    return $ret;

}

#--------------------------------------------------------------------#

sub _load_manual {

    my $manual = {
        jsonfile  => qq(The path and name of the JSON input file),
    };

    return $manual;

}

#--------------------------------------------------------------------#

sub _print_info {

    my %args = @_;
    my $hinput = $args{Input} || die whoami();
    my $show_help_info = $args{ShowHelpInfo};

    my %input = %{$hinput};

    my $manual = _load_manual();

    if ($show_help_info) {
    print "\n
    Type perl $0.pl -info=ITEM to get help.\n
    The help is available for the following ITEMS:
        * jsonfile   : the path and name of the JSON file with input
        \n";
        exit;

    };

    return unless ($input{info});

    my $item = $input{info} || '';

    return unless ($item);

    my $content = $manual->{$item} || '';
 
    print "** $item **\n";
    if ($content) {
        print $manual->{$item},"\n";
    } else {
        print "No manual entry.\n";
    }
     
    exit;

}

#--------------------------------------------------------------------#

sub read_json_file {

    my %args = @_;
    my $file = $args{File};

    local $/;
    my $fh = FileHandle->new;
    open ($fh,"<$file") or die whoami()."$file: $!";
    my $json_text = <$fh>;
    close ($fh);
    my $json = decode_json( $json_text );

    return $json;

}

#-------------------------------------------------------------------

sub node {

    # This subroutine calculates the closest grid node coordinate

    my %args = @_;

    my $val = $args{Value};
    my $grid_size = $args{GridSize};

    my $grid = $val / $grid_size;
    my $int_grid = POSIX::floor($grid);
    my $node = $int_grid * $grid_size;

    return $node;

}

#--------------------------------------------------------------------#

sub set_info {

    my %args = @_;

    my $hinfo = $args{Info} || die whoami();
    my $hinput = $args{Input} || die whoami();
    my $logger = $args{Logger} || die whoami();

    my %info = %{$hinfo};
    my %input = %{$hinput};
 
    my $ret = {
        info => \%info,
        input => $hinput
    };

    return $ret;

}

#--------------------------------------------------------------------#

sub _variable_node_index {

    my %args = @_;

    my $pos;
    my $starting_byte;

    #    ENSEMBLE AIR QUALITY

    # Data in files are stored as matrices, preceded by the date and time record
    # The position in the file of value(x,y,t) is:
    #my $nx = ($xmax - $xmin) / $dx + 1;
    #my $pos = (($ymax - $y) / $dy) * $nx + (($x - $xmin) / $dx) + t * $ny * (14*$nx +1) * ;

    # t is a positive index

    my $nmat = $args{BytesLine} * $args{NyDomain};
    my $nbefore = ($nmat + 13) * ($args{T} - 1);

    $pos = POSIX::floor ( 0.5 +
                   POSIX::floor( 0.5 + (($args{YmaxDomain} - $args{Y}) / $args{DyDomain}) ) * ( $args{NxDomain} * 14 + 1)
                 + POSIX::floor( 0.5 + (($args{X} - $args{XminDomain}) / $args{DxDomain}) * 14 )
              );
    die Dumper \%args,$pos if ($pos < 0);

    #The starting byte is:

    $starting_byte = $nbefore + 13 + $pos;

    return $starting_byte;

}

#------------------------------------------------------
sub get_files {

    my %args = @_;
    # These are mandatory inputs
    die " GeneralPurpose.pm (get_files) - Dir is mandatory".Dumper caller() unless ($args{Dir});
    
    my $dir = $args{Dir};
    my $filter = $args{Filter} || '';

    opendir(DIR, $dir) or die "$dir: $!";
    my @list = grep { $_ ne "." and $_  ne ".." } readdir(DIR);
    closedir(DIR);
  
    if ($filter) {
        @list = grep /$filter/, @list;
    }

    if (exists($args{IncludePath})) {
        my @new_list = ();
        foreach my $item (@list) {        
            push @new_list, $dir.$item;
        }
        @list = @new_list;
    }
    return @list;

}

#--------------------------------------------------------------------#

sub whoami { ( caller(1) )[3]." - " }

1;

