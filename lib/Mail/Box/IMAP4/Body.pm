use strict;
use warnings;

package Mail::Box::IMAP4::Body;
use vars '$VERSION';
$VERSION = '2.052';
use base 'Mail::Message::Body::Lines';

use Scalar::Util 'weaken';


sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    my $write = exists $args{write_body} ? $args{write_body} : 1;

    $self->writeBody if $self->{MBIB_write_body};
    delete $self->{MMBL_array} unless $self->{MBIB_cache_body};

    $self;
}

#------------------------------------------


sub guessSize()   { undef }

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
