
use strict;
use warnings;

package Mail::Box::Message;
use vars '$VERSION';
$VERSION = '2.049';
use base 'Mail::Message';

use Date::Parse;
use Scalar::Util 'weaken';


sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->{MBM_deleted}    = $args->{deleted}   || 0;

    $self->{MBM_body_type}  = $args->{body_type}
        if exists $args->{body_type};

    $self->{MBM_folder}     = $args->{folder};
    weaken($self->{MBM_folder});

    return $self if $self->isDummy;

    $self;
}

#-------------------------------------------


sub coerce($)
{   my ($class, $message) = @_;
    return bless $message, $class
        if $message->isa(__PACKAGE__);

    my $coerced = $class->SUPER::coerce($message);
    $coerced->{MBM_deleted} = 0;
    $coerced;
}

#-------------------------------------------

sub head(;$)
{   my $self  = shift;
    return $self->SUPER::head unless @_;

    my $new   = shift;
    my $old   = $self->head;
    $self->SUPER::head($new);

    return unless defined $new || defined $old;

    my $folder = $self->folder
        or return $new;

    if(!defined $new && defined $old && !$old->isDelayed)
    {   $folder->messageId($self->messageId, undef);
        $folder->toBeUnthreaded($self);
    }
    elsif(defined $new && !$new->isDelayed)
    {   $folder->messageId($self->messageId, $self);
        $folder->toBeThreaded($self);
    }

    $new || $old;
}

#-------------------------------------------


sub folder(;$)
{   my $self = shift;
    if(@_)
    {   $self->{MBM_folder} = shift;
        weaken($self->{MBM_folder});
        $self->modified(1);
    }
    $self->{MBM_folder};
}

#-------------------------------------------


sub seqnr(;$)
{   my $self = shift;
    @_ ? $self->{MBM_seqnr} = shift : $self->{MBM_seqnr};
}

#-------------------------------------------


sub copyTo($)
{   my ($self, $folder) = @_;
    $folder->addMessage($self->clone);
}

#-------------------------------------------


sub moveTo($)
{   my ($self, $folder) = @_;
    my $added = $folder->addMessage($self->clone);
    $self->delete;
    $added;
}

#-------------------------------------------


sub delete() { shift->{MBM_deleted} ||= time }

#-------------------------------------------


sub deleted(;$)
{   my $self = shift;

      ! @_      ? $self->isDeleted   # compat 2.036
    : ! (shift) ? ($self->{MBM_deleted} = undef)
    :             $self->delete;
}

#-------------------------------------------


sub isDeleted() { shift->{MBM_deleted} }

#-------------------------------------------


sub readBody($$;$)
{   my ($self, $parser, $head, $getbodytype) = @_;

    unless($getbodytype)
    {   my $folder   = $self->{MBM_folder};
        $getbodytype = sub {$folder->determineBodyType(@_)};
    }

    $self->SUPER::readBody($parser, $head, $getbodytype);
}

#-------------------------------------------


sub diskDelete() { shift }

#-------------------------------------------

sub forceLoad() {   # compatibility
   my $self = shift;
   $self->loadBody(@_);
   $self;
}

#-------------------------------------------


sub destruct()
{   require Mail::Box::Message::Destructed;
    Mail::Box::Message::Destructed->coerce(shift);
}

#-------------------------------------------

1;
