# Calculates the longest range that contains all the integers in the input array.
# See also: http://stackoverflow.com/questions/5415305/finding-contiguous-ranges-in-arrays
# This implementation: O(n) operations, O(n) memory and branch-free.

use strict;
use warnings;

my @n = (2, 10, 3, 12, 5, 4, 11, 8, 7, 6, 15); # test from stackoverflow
# various other tests
#@n = (1,2,3,5,6,7,8); # second list longer than first
#@n = (5,6,7,8,1,2,3); # first list longer than second
#@n = (1,2,3,5,6,7,8,4); # last element links up 2 lists
#@n = (1,2,3,10,11,12,13,5,6,7); # longest list is middle one

my %forward;
my %backward;

my $longest = $n[0];
for my $i (@n) {

    # point at myself, or what my successor points at
    my $forward_val = $forward{ $i+1 };
    $forward_val += -!$forward_val & $i; # taking advantage of undef to 0 promotion in inc (foo = undef + 2 warns)
    $forward{ $i } = $forward_val; 

    # point at myself or what my predecessor points at
    my $backward_val = $backward{ $i-1 };
    $backward_val += -!$backward_val & $i;
    $backward{ $i } = $backward_val;

    # point the end of this range to the start
    $backward{ $forward{ $i } } = $backward{ $i };

    # point the start to the end
    $forward{ $backward{ $i } } = $forward{ $i };
    
    # update the current longest chain
    my $is_longer = $forward{ $i } - $backward{ $i } > $forward{ $longest } - $backward{ $longest };
    $longest = (-$is_longer & $backward{ $i }) + (($is_longer-1) & $longest);
}

print "Longest range: $longest -> $forward{$longest}\n";