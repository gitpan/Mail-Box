use strict;
use warnings;

package Mail::Box::IMAP4::DelayedBody;
use vars '$VERSION';
$VERSION = '2.052';
use base 'Mail::Message::Body::Delayed';

use Scalar::Util 'weaken';


sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);
    $self;
}

#------------------------------------------


sub guessSize()   {shift->{MMBD_size}}

#------------------------------------------


sub read($$;$@)
{   my ($self, $parser, $head, $bodytype) = splice @_, 0, 4;
    $self->{MMBD_parser} = $parser;

    @$self{ qw/MMBD_begin MMBD_end MMBD_size MMBD_lines/ }
        = $parser->bodyDelayed(@_);

    $self;
}

#------------------------------------------


sub load() {$_[0] = $_[0]->message->loadBody}

#------------------------------------------


1;
