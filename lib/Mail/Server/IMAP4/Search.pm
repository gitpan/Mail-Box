# Copyrights 2001-2014 by [Mark Overmeer].
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 2.01.

use strict;
use warnings;

package Mail::Server::IMAP4::Search;
our $VERSION = '2.112';

use base 'Mail::Box::Search';


sub init($)
{   my ($self, $args) = @_;
    $self->notImplemented;
}

#-------------------------------------------

1;
