use strict;
use warnings;

package Mail::Box::Net::Message;
our $VERSION = 2.031;  # Part of Mail::Box
use base 'Mail::Box::Message';

use File::Copy;
use Carp;

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);

    my $unique = $args->{unique}
        or croak "No unique keys for this net message.";

    $self->unique($unique);

    $self;
}

sub unique(;$)
{   my $self = shift;
    @_ ? $self->{MBNM_unique} = shift : $self->{MBNM_unique};
}

sub loadHead()
{   my $self     = shift;
    my $head     = $self->head;
    return $head unless $head->isDelayed;

    my $folder   = $self->folder;
    $folder->lazyPermitted(1);

    my $parser   = $self->parser or return;
    $self->readFromParser($parser);

    $folder->lazyPermitted(0);

    $self->log(PROGRESS => 'Loaded delayed head.');
    $self->head;
}

sub loadBody()
{   my $self     = shift;

    my $body     = $self->body;
    return $body unless $body->isDelayed;

    my $head     = $self->head;
    my $parser   = $self->parser or return;

    if($head->isDelayed)
    {   $head = $self->readHead($parser);
        if(defined $head)
        {   $self->log(PROGRESS => 'Loaded delayed head.');
            $self->head($head);
        }
        else
        {   $self->log(ERROR => 'Unable to read delayed head.');
            return;
        }
    }
    else
    {   my ($begin, $end) = $body->fileLocation;
        $parser->filePosition($begin);
    }

    my $newbody  = $self->readBody($parser, $head);
    unless(defined $newbody)
    {   $self->log(ERROR => 'Unable to read delayed body.');
        return;
    }

    $self->log(PROGRESS => 'Loaded delayed body.');
    $self->storeBody($newbody);
}

1;
