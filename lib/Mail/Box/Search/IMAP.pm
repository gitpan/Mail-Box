
package Mail::Box::Search::IMAP;
use vars '$VERSION';
$VERSION = '2.048';
use base 'Mail::Box::Search';

use strict;
use warnings;

use Carp;

#-------------------------------------------


sub init($)
{   my ($self, $args) = @_;
    $self->notImplemented;
}

#-------------------------------------------

1;
