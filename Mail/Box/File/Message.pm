use strict;
package Mail::Box::File::Message;
our $VERSION = 2.038;  # Part of Mail::Box
use base 'Mail::Box::Message';

use POSIX 'SEEK_SET';
use Carp;

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->fromLine($args->{from_line})
        if exists $args->{from_line};

    $self;
}

sub coerce($)
{   my ($self, $message) = @_;
    return $message if $message->isa(__PACKAGE__);

    $self->SUPER::coerce($message)->labelsToStatus;
}

sub write(;$)
{   my $self  = shift;
    my $out   = shift || select;

    $out->print($self->fromLine);
    $self->head->print($out);
    $self->body->printEscapedFrom($out);
    $out->print("\n");
    $self;
}

sub clone()
{   my $self  = shift;
    my $clone = $self->SUPER::clone;
    $clone->{MBMM_from_line} = $self->{MBMM_from_line};
    $clone;
}

sub head(;$$)
{   my $self  = shift;
    return $self->SUPER::head unless @_;

    my ($head, $labels) = @_;
    $self->SUPER::head($head, $labels);
    $self->statusToLabels if $head && !$head->isDelayed;
    $head;
}

sub label(@)
{   my $self   = shift;
    my $return = $self->SUPER::label(@_);
    $self->labelsToStatus if @_ > 1;
    $return;
}

sub fromLine(;$)
{   my $self = shift;

    $self->{MBMM_from_line} = shift if @_;
    $self->{MBMM_from_line} ||= $self->head->createFromLine;
}

sub readFromParser($)
{   my ($self, $parser) = @_;
    my ($start, $fromline)  = $parser->readSeparator;
    return unless $fromline;

    $self->{MBMM_from_line} = $fromline;
    $self->{MBMM_begin}     = $start;

    $self->SUPER::readFromParser($parser) or return;
    $self;
}

sub loadHead() { shift->head }

sub loadBody()
{   my $self     = shift;

    my $body     = $self->body;
    return $body unless $body->isDelayed;

    my ($begin, $end) = $body->fileLocation;

    my $parser   = $self->folder->parser;
    $parser->filePosition($begin);

    my $newbody  = $self->readBody($parser, $self->head);
    unless($newbody)
    {   $self->log(ERROR => 'Unable to read delayed body.');
        return;
    }

    $self->log(PROGRESS => 'Loaded delayed body.');
    $self->storeBody($newbody);

    $newbody;
}

sub fileLocation()
{   my $self = shift;

    wantarray
     ? ($self->{MBMM_begin}, ($self->body->fileLocation)[1])
     : $self->{MBMM_begin};
}

sub moveLocation($)
{   my ($self, $dist) = @_;
    $self->{MBMM_begin} -= $dist;

    $self->head->moveLocation($dist);
    $self->body->moveLocation($dist);
    $self;
}

1;
