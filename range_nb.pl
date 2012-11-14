# Calculates the longest range that contains all the integers in the input array.
# See also: http://stackoverflow.com/questions/5415305/finding-contiguous-ranges-in-arrays
# This implementation: O(n) operations, O(n) memory and branch-free.

use strict;
use warnings;

my @n = (2, 10, 3, 12, 5, 4, 11, 8, 7, 6, 15);

my %forward;
my %backward;

my $longest = $n[0];
for my $i (@n) {

    # point at myself, or what my succ points at
    my $forward_val = $forward{ $i+1 };
    $forward_val += -!$forward_val & $i; # taking advantage of undef to 0 promotion in inc (foo = undef + 2 warns)
    $forward{ $i } = $forward_val; 
    
    # correct the endpoint to point back at the backmost
    $backward{ $forward{ $i } } = $backward{ $i };
  
    # point at myself or what my pred points at
    my $backward_val = $backward{ $i-1 };
    $backward_val += -!$backward_val & $i;
    $backward{ $i } = $backward_val; 

    # correct the start to point at farthest forward
    $forward{ $backward{ $i } } = $forward{ $i };

    # do both again to fixup propagations    
    $backward{ $forward{ $i } } = $backward{ $i }; # correct the endpoint to point back at the backmost
    $forward{ $backward{ $i } } = $forward{ $i }; # correct the start to point at farthest forward
    
    # update the current longest chain
    my $is_longer = $forward{ $i } - $backward{ $i } > $forward{ $longest } - $backward{ $longest };
    my $l2 = -$is_longer & $backward{ $i };
    $longest += $l2 - ($l2 > 0) & $longest; 
}

print "Longest range: $longest -> $forward{$longest}\n";