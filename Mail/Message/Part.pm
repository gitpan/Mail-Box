use strict;
use warnings;

package Mail::Message::Part;
our $VERSION = 2.040;  # Part of Mail::Box
use base 'Mail::Message';

use Carp;

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    confess "No container specified for part.\n"
        unless exists $args->{container};

    $self->{MMP_container} = $args->{container};
    $self;
}

sub buildFromBody($$;@)
{   my ($class, $body, $container) = (shift, shift, shift);
    my @log     = $body->logSettings;

    my $head    = Mail::Message::Head::Complete->new(@log);
    while(@_)
    {   if(ref $_[0]) {$head->add(shift)}
        else          {$head->add(shift, shift)}
    }

    my $part = $class->new
     ( head      => $head
     , container => $container
     , @log
     );

    $part->body($body);
    $part;
}

sub coerce($@)
{   my ($class, $thing, $container) = (shift, shift, shift);

    return $class->buildFromBody($thing, $container, @_)
        if $thing->isa('Mail::Message::Body');

    # Although cloning is a Bad Thing(tm), we must avoid modifying
    # header fields of messages which reside in a folder.
    my $message = $thing->isa('Mail::Box::Message') ? $thing->clone : $thing;

    my $part    = $class->SUPER::coerce($message);
    $part->{MMP_container} = $container;
    $part;
}

sub delete() { shift->{MMP_deleted} ||= time }

sub deleted(;$)
{   my $self = shift;
      ! @_      ? $self->isDeleted   # compat 2.036
    : ! (shift) ? ($self->{MMP_deleted} = undef)
    :             $self->delete;
}

sub isDeleted() { shift->{MMP_deleted} }

sub container(;$)
{   my $self = shift;
    @_ ? $self->{MMP_container} = shift : $self->{MMP_container};
}

sub toplevel()
{   my $body = shift->container or return;
    my $msg  = $body->message   or return;
    $msg->toplevel;
}

sub isPart() { 1 }

sub printEscapedFrom($)
{   my ($self, $out) = @_;
    $self->head->print($out);
    $self->body->printEscapedFrom($out);
}

sub readFromParser($;$)
{   my ($self, $parser, $bodytype) = @_;

    my $head = $self->readHead($parser)
            || Mail::Message::Head::Complete->new
                 ( message     => $self
                 , field_type  => $self->{MM_field_type}
                 , $self->logSettings
                 );

    my $body = $self->readBody($parser, $head, $bodytype)
            || Mail::Message::Body::Lines->new(data => []);

    $self->head($head);
    $self->storeBody($body);
    $self;
}

1;
