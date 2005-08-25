
use strict;
use warnings;

package Mail::Server::IMAP4::Search;
use vars '$VERSION';
$VERSION = '2.062';
use base 'Mail::Box::Search';


sub init($)
{   my ($self, $args) = @_;
    $self->notImplemented;
}

#-------------------------------------------

1;
