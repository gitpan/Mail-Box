
package Mail::Box::Tie;
use vars '$VERSION';
$VERSION = '2.046';

use strict;

use Carp;


#-------------------------------------------

sub TIEHASH(@)
{   my $class = (shift) . "::HASH";
    eval "require $class";   # bootstrap

    confess $@ if $@;
    $class->TIEHASH(@_);
}

#-------------------------------------------

sub TIEARRAY(@)
{   my $class = (shift) . "::ARRAY";
    eval "require $class";   # bootstrap

    confess $@ if $@;
    $class->TIEARRAY(@_);
}

#-------------------------------------------

1;
