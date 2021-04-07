package Library;

# Author: R.Bianconi - Enviroware srl

use strict;
require Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw(
    anytrim
    check_input
    extract_values_from_grid
    init_input
    load_sq_json_file
    load_receptors
    node
    set_info

);
our @EXPORT_OK = qw();
my $VERSION = '20210407';

use Data::Dumper;
use Tie::File;
use FileHandle;
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

sub extract_values_from_grid {

    my %args = @_;

    my $dat_file = $args{DatFile};
    my @xs = @{$args{Xs}};
    my @ys = @{$args{Ys}};
    my @ts = @{$args{Ts}};
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

    my $nmat = $args{BytesLine} * $args{NyDomain};
    my $nbefore = ($nmat + 13) * $args{T};

    $pos = POSIX::floor ( 0.5 +
                   POSIX::floor( 0.5 + (($args{YmaxDomain} - $args{Y}) / $args{DyDomain}) ) * ( $args{NxDomain} * 14 + 1)
                 + POSIX::floor( 0.5 + (($args{X} - $args{XminDomain}) / $args{DxDomain}) * 14 )
              );
    die $pos, Dumper \%args if ($pos < 0);

    #The starting byte is:

    $starting_byte = $nbefore + 13 + $pos;

    return $starting_byte;

}

#--------------------------------------------------------------------#

sub whoami { ( caller(1) )[3]." - " }

1;

