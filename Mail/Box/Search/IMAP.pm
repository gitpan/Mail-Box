package Mail::Box::Search::IMAP;
our $VERSION = 2.033;  # Part of Mail::Box
use base 'Mail::Box::Search';

use strict;
use warnings;

use Carp;

sub init($)
{   my ($self, $args) = @_;
    $self->notImplemented;
}

1;
