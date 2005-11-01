
use strict;
use warnings;

package Mail::Server::IMAP4::Search;
use vars '$VERSION';
$VERSION = '2.063';
use base 'Mail::Box::Search';


sub init($)
{   my ($self, $args) = @_;
    $self->notImplemented;
}

#-------------------------------------------

1;
