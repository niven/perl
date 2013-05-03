use strict;
use warnings FATAL => 'all';

use Data::Dumper;

local $\ = "\n";

my ($UNVISITED, $NORTH, $EAST, $SOUTH, $WEST, $UP, $DOWN, $BLOCKED) = 
(
    0b00000000,
    0b00100000,
    0b01000000,
    0b01100000,
    0b10000000,
    0b10100000,
    0b11000000,
    0b11100000
);

print "Cell markers: $UNVISITED, $NORTH, $EAST, $SOUTH, $WEST, $UP, $DOWN, $BLOCKED";

my ($target) = @ARGV;

my ($grid, $netlist) = ( "$target.grid", "$target.nl" );

print "Grid $grid, netlist: $netlist";

open(my $GRID, "<", $grid) or die $!;

# width, height, bend_cost, via_cost just global since it is a property of the grids
my ($width, $height, $bend_cost, $via_cost) = split / /, <$GRID>;

print "X width: $width, Y height: $height, Bend: $bend_cost, Via: $via_cost";

my $debug = $height < 20; # only dump stuff for small grids

my @grids; # this is just global since we need it everywhere anyway

# read the grid, layer 1 and 2
for my $g ( 0 .. 1) {
    my @grid;
    for my $y (0 .. $height-1) {
        my $x = 0;
        my $line = <$GRID>;
        $line =~ s/^\s*//;
        $line =~ s/\s*$//;
        map { $grid[ $x++ + $y*$width ] = 0+$_; } split /\s+/, $line;
    }
    $grids[ $g ] = \@grid;
}

while(<$GRID>) {
	print "Leftover: $_";
}

close($GRID);

my $num_layers = scalar @grids;

print "Layers: $num_layers";
print "Layer1\n" . pretty($grids[0]) if $debug;
print "Layer2\n" . pretty($grids[1]) if $debug;

open(my $NL, "<", $netlist) or die $!;

my @nets;
my $nets = <$NL> + 0;
print "Nets: $nets";

for my $n (1 .. $nets) {
    
    my $net = {};
    my $line = <$NL>;
    $line =~ s/\s+$//;
    $line =~ s/^\s+//;
    my ($i, $a, $b, $c, $d, $e, $f) = map 0+$_, split /\s+/, $line;
    
    push @nets, { start => [$a, $b, $c], end => [$d, $e, $f] };
}

close($NL);

print Dumper(\@nets) if $debug;

#my @paths = ( route_net($nets[0]) );


my @paths = map route_net($_), @nets;

open(my $RESULT, ">", "$target.result");

print $RESULT scalar @paths;

my $n=1;
my $routed = 0;
for my $p (@paths) {
	$routed++ if scalar @$p > 0;
    print $RESULT $n++;
    print $RESULT "@$_" for @$p;
    print $RESULT 0;
}

close($RESULT);

print "Routed $routed nets";

print "Layer1\n" . pretty($grids[0]) if $debug;
print "Layer2\n" . pretty($grids[1]) if $debug;

print "Done";

# set blocked to -1 after we find the path

# How do we keep track of stuff in the cells of the grid?
# copy of grid? modify the grid contents? smart things with masks?
# I'm going to go with masks, since the highest cost I've seen is 30, we can use 5 bits for the cost
# then 3 bits for the from-direction (N,E,S,W,U,D). When the direction is set it can double as "visited" so
# we save a bit there. total=8 bits which is cool. Cell costs of -1 masked with 0b11100000 will then count
# as blocked but still distinguishable from a direction.
# X: 0b000 00000 Unvisited
# N: 0b001 00000
# E: 0b010 00000
# S: 0b011 00000
# W: 0b100 00000
# U: 0b101 00000
# D: 0b110 00000
# B: 0b111 00000 (Blocked) (-1 & 0b11100000 == 0b11100000)
# this all works out rather nicely!

# Note: to find out if we are making a bend we have to remember for each cell we're going to expand what direction we came from
sub route_net {
    
    my ($net) = @_;
    
    # first unblock start and end
    $grids[ $net->{start}->[0]-1 ]->[ $net->{start}->[1] + $net->{start}->[2]*$width ] = 1;
    $grids[ $net->{end}->[0]-1 ]->[ $net->{end}->[1] + $net->{end}->[2]*$width ] = 1;
    
    # this is a set current locations as [layer, x, y, cost_sum, prev_direction]
    print "Setting wavefront to initial cell" if $debug;
    my $wavefront = [ [ @{$net->{start}}, gridvalue( @{$net->{start}}), $UNVISITED ] ]; # this should always be just a value, don't need to mask
    $grids[ $net->{start}->[0]-1 ]->[ $net->{start}->[1] + $net->{start}->[2]*$width ] = -1; # start location now blocked so we don't re-expand there
    print Dumper("Routing a net:", $wavefront) if $debug;
    
    my $target_hit = 0;
    
    # expand until we reach the target (or run out of wavefront)
    # 1. find/remove all the current cells with the lowest costs (could be more than one) (and these should be first in the list)
    # 2. expand all of them, and keep track of new locations in a hash so we can see which ones overlap
    # 3. reduce the hash to single reached cells by picking the cheapest one
    # 4. add the result to the wavefront, but make sure to insert them sorted (we could use a heap, but insertion sort is easy enough) ? Is this true?
    # 5. check the result against the target (we only need to check the newly reached cells of course)
    my $it = 0;
    while ( !$target_hit && scalar @$wavefront > 0 ) {
        print "============== Expanding iteration " . $it++ . " ========================" if $debug;
        my $lowest_cost = grep { $wavefront->[0]->[3] == $_->[3] } @$wavefront; # everything in cost equal to first
        print "Num lowest cost: $lowest_cost" if $debug;
        my @lowest_cost_endpoints = splice(@$wavefront, 0, $lowest_cost); # remove them
        print Dumper("Expanding", \@lowest_cost_endpoints) if $debug;
        print Dumper("Wavefront left:", $wavefront) if $debug;
        
        my %expanded; # key is layer_index, value is list of things that expand here
        for my $endpoint (@lowest_cost_endpoints) {
            push @{ $expanded{ $_->[0] . "_" . ($_->[1]+$_->[2]*$width) } }, $_ for expand( $endpoint );
        }
        print Dumper("Expansions done", \%expanded) if $debug;
        
        # now go over all expansions and prune those that reach the same cells but with higher cost
        my @results;
        for my $key (keys %expanded) {
            my $reached = $expanded{ $key };
            if( @$reached > 1 ) {
#                print Dumper("Pruning", $reached);
                @$reached = sort { $a->[3] <=> $b->[3] } @$reached;
                @$reached = grep { $_->[3] == $reached->[0]->[3] } @$reached; # keep cheap
#                print Dumper("sorted by cost: ", $reached);
                push @results, $reached->[ int( rand() * scalar @$reached ) ]; # pick any of cheapest
            } else {
                push @results, @$reached;
            }
        }
        
        print Dumper("Cost prune done", \@results) if $debug;
        
        # check if we hit the target
#        print "Did we hit: @{$net->{end}}";
        $target_hit = grep {
#                    print "@{$net->{end}} == @$_ ?"; 
                    $net->{end}->[0] == $_->[0] &&  # layer
                    $net->{end}->[1] == $_->[1] &&  # x
                    $net->{end}->[2] == $_->[2]     # y
                } @results;
        
        print "Hit target: $target_hit" if $debug;
        
#        $target_hit = $it == 3;

        # mark all newly reached grid cells so we won't expand there anymore
        for my $c (@results) {
            $grids[ $c->[0]-1 ]->[ $c->[1] + $c->[2]*$width ] |= $c->[4]; # OR in the direction we took to get here
        }
        print pretty( $grids[0] ) if $debug;
    
        # add all reached cells to the wavefront
        # sort them
        @results = sort { $a->[3] <=> $b->[3] } @results;
        print Dumper("reached sorted by cost", \@results) if $debug;
        print Dumper("leftover wavefront", $wavefront) if $debug;

        # merge the results with the wavefront, keeping them in sorted order
        my @new_wavefront;
        while( scalar @results > 0 && scalar @$wavefront > 0 ) {
            push @new_wavefront, ( $results[0]->[3] < $wavefront->[0]->[3] ? shift @results : shift @$wavefront );
        }
        push @new_wavefront, @results;
        push @new_wavefront, @$wavefront;

        print Dumper("new wavefront:", \@new_wavefront) if $debug;
        $wavefront = \@new_wavefront;
    }
    
    if( !$target_hit ) {
        return []; # sadface
    }
    
    # build the path back from the target
    # we can just start at $net->{end} since we know it is now marked on the grid
    my @path;
    my $current = $net->{end};
    print "@{$net->{end}} has grid value: " . gridvalue( @$current ) if $debug;
    while ( ! ($current->[0] == $net->{start}->[0] && $current->[1] == $net->{start}->[1] && $current->[2] == $net->{start}->[2]) ) {
        my $gv = gridvalue( @$current );
        my $from_dir = $gv & 0b11100000;
        print "Backtracing from @$current, from = $from_dir" if $debug;
        unshift @path, $current;
        $current = backtrace( $current, $from_dir );
        print "Backed up to @$current" if $debug;
    }
    # don't forget to add in the start
    unshift @path, $net->{start};
    print pretty($grids[0]) if $debug;
    # unblock every other cell. Really? there must be a better way :(
    for my $g (@grids) {
        $g->[$_] = ($g->[$_] == -1 ? -1 : $g->[$_] & 0b0011111) for 0 .. ((scalar @$g) -1);
    }    
    print pretty($grids[0]) if $debug;
    # block the cells on the path    
    for my $p (@path) {
        $grids[ $p->[0]-1 ]->[ $p->[1] + $p->[2]*$width ] = -1;
    }
    print pretty($grids[0]) if $debug;
    
    return \@path;
    
}

# back a cell in the direction we came from
# the grid is marked with the direction we took to get here, not the direction we need to go to get back
# (which maybe is dumb)
sub backtrace {
    my ($current, $dir) = @_;
    
    if( $dir == $NORTH ) {
        return [ $current->[0], $current->[1], $current->[2]-1 ];
    }
    if( $dir == $SOUTH ) {
        return [ $current->[0], $current->[1], $current->[2]+1 ]; 
    }
    if( $dir == $EAST ) {
        return [ $current->[0], $current->[1]-1, $current->[2] ]; 
    }
    if( $dir == $WEST ) {
        return [ $current->[0], $current->[1]+1, $current->[2] ]; 
    }
    if( $dir == $UP ) {
        return [ $current->[0]+1, $current->[1], $current->[2] ]; 
    }
    if( $dir == $DOWN ) {
        return [ $current->[0]-1, $current->[1], $current->[2] ]; 
    }
    
    die "Unable to backtrace from @$current with dir $dir"; # cannot happen ;)
}

# expand a cell in all directions (N,S,E,W,U,D)
# where not blocked/visited, taking into account bend costs and vias
# grid:      (w,h)
# h +--+--+--+--+
# ^ |  |  |  |  |
# | +--+--+--+--+
# 0 |  |  |  |  |
# y +--+--+--+--+
#   x 0   ->    w

sub expand {
    
    my ($endpoint) = @_;
    
    print "Expanding cell @$endpoint" if $debug;
    
    my @expansions;
    my $gv;

    # try to go 6 directions ( cells are [layer, x, y, cost, from]
    if( $endpoint->[1] < $width-1 ) { # east (x < width)
        push @expansions, go( [ $endpoint->[0], $endpoint->[1]+1, $endpoint->[2], $endpoint->[3], $EAST ], $endpoint );
    }
    if( $endpoint->[1] > 0 ) { # west (x > 0)
        push @expansions, go( [ $endpoint->[0], $endpoint->[1]-1, $endpoint->[2], $endpoint->[3], $WEST ], $endpoint );
    }
    if( $endpoint->[2] < $height-1 ) { # north (y < $height )
        push @expansions, go( [ $endpoint->[0], $endpoint->[1], $endpoint->[2]+1, $endpoint->[3], $NORTH ], $endpoint );
    }
    if( $endpoint->[2] > 0 ) { # south (y > 0 )
        push @expansions, go( [ $endpoint->[0], $endpoint->[1], $endpoint->[2]-1, $endpoint->[3], $SOUTH ], $endpoint );
    }
    if( $endpoint->[0] > 1 ) { # up (layers > 1 ) (up goes towards layer 1)
        push @expansions, go( [ $endpoint->[0]-1, $endpoint->[1], $endpoint->[2], $endpoint->[3], $UP ], $endpoint );
    }
    if( $endpoint->[0] < $num_layers ) { # down (layers < num_layers )
        push @expansions, go( [ $endpoint->[0]+1, $endpoint->[1], $endpoint->[2], $endpoint->[3], $DOWN ], $endpoint );
    }
#    print Dumper("Expansions", \@expansions);
    
    return @expansions;
}

# go in the direction of newcell if we can, otherwise return empty list
sub go {
    my ($newcell, $endpoint) = @_;

    my $gv = gridvalue( $newcell->[0], $newcell->[1], $newcell->[2] );
    if( ($gv & 0b11100000) == 0 ) { # -1 if blocked, some other value if visited
        my $cost = cost_to_expand_here( $newcell, $gv, $endpoint );
        $newcell->[3] += $cost;
        return $newcell;
    } else {
        print "Cell blocked: @$newcell" if $debug;
    }
    
    
    return ();
}

sub cost_to_expand_here {
    my ($target, $gridvalue, $from) = @_;
    
    my $bends = $target->[4] != $from->[4] && $from->[4] != 0 ? 1 : 0; # ?! to avoid undef-false
    my $via = $target->[0] != $from->[0] ? 1 : 0;
    
    my $cost = ($bends ? $bend_cost : 0) + ($via ? $via_cost : 0) + $gridvalue;

    print "CTE (bend: $bends, via: $via, cost: $cost) target: (@$target), from: (@$from), GV: $gridvalue" if $debug;
    
    return $cost;
}

# grid value (cost + pathing stuff)
# (could be optimized, don't care)
# layer input is 1 based
sub gridvalue {
    my ($layer, $x, $y) = @_;
    
    my $grid = $grids[ $layer-1 ];
    my $index = $x + $width*$y;

#    print "Gridval for $layer, $x, $y = $grid->[ $index ]";
    return $grid->[ $index ];
}

# prettyfmt grid
sub pretty {
    
    my ($grid) = @_;
    
    my $out = "";
    print scalar @$grid . " w: ". $width;
    
    for my $y ( reverse 0 .. (scalar @$grid / $width-1)) {
#        print "int: " . ($y*($width)) . "-" . (($y+1)*($width)-1);
		$out .= "$y: ";
        $out .= join("", map { sprintf("% 2d ", $_) } @{$grid}[ $y*($width) .. ($y+1)*($width)-1 ]);
        $out .= "\n";
#        print $out;
    }
    
    return $out;    
}