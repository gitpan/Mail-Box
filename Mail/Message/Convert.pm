use strict;
use warnings;

package Mail::Message::Convert;
our $VERSION = 2.032;  # Part of Mail::Box
use base 'Mail::Reporter';

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->{MMC_fields}          = $args->{fields}    ||
       qr#^(Resent\-)?(To|From|Cc|Bcc|Subject|Date)\b#i;

    $self;
}

sub selectedFields($)
{   my ($self, $head) = @_;
    $head->grepNames($self->{MMC_fields});
}

1;
