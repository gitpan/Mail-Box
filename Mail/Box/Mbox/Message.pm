
use strict;
package Mail::Box::Mbox::Message;
use base 'Mail::Box::Message';

our $VERSION = 2.016;

use POSIX 'SEEK_SET';
use Carp;

=head1 NAME

Mail::Box::Mbox::Message - one message in a Mbox folder

=head1 CLASS HIERARCHY

 Mail::Box::Mbox::Message
 is a Mail::Box::Message
 is a Mail::Message + ::Construct
 is a Mail::Reporter

=head1 SYNOPSIS

 my $folder  = new Mail::Box::Mbox folder => $ENV{MAIL}, ...;
 my $message = $folder->message(0);

=head1 DESCRIPTION

Maintain one message in an Mbox folder.  See the C<Mail::Message>
documentation for exceptions and extensions to messages which are
Mbox-specific on this page.

The bottom of this page provides more
L<details about the implementation|/"IMPLEMENTATION">, but first the use.

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Message> (MM), L<Mail::Reporter> (MR), L<Mail::Box::Message> (MBM), L<Mail::Message::Construct> (MMC).

The general methods for C<Mail::Box::Mbox::Message> objects:

   MM bcc                              MMC lines
  MMC bounce OPTIONS                    MR log [LEVEL [,STRINGS]]
  MMC build [MESSAGE|BODY], CONTENT     MM messageId
  MMC buildFromBody BODY, HEADERS       MM modified [BOOL]
   MM cc                                   new OPTIONS
  MBM copyTo FOLDER                     MM nrLines
   MM date                              MM parent
   MM decoded OPTIONS                   MM parts
  MBM delete                               print [FILEHANDLE]
  MBM deleted [BOOL]                   MMC printStructure [INDENT]
   MM destinations                     MMC read FILEHANDLE|SCALAR|REF-...
   MM encode OPTIONS                   MMC reply OPTIONS
   MR errors                           MMC replyPrelude [STRING|FIELD|...
  MMC file                             MMC replySubject STRING
  MBM folder [FOLDER]                   MR report [LEVEL]
  MMC forward OPTIONS                   MR reportAll [LEVEL]
  MMC forwardPostlude                   MM send [MAILER], OPTIONS
  MMC forwardPrelude                   MBM seqnr [INTEGER]
  MMC forwardSubject STRING            MBM shortString
   MM from                              MM size
      fromLine [LINE]                  MMC string
   MM get FIELD                         MM subject
   MM guessTimestamp                    MM timestamp
   MM isDummy                           MM to
   MM isMultipart                       MM toplevel
   MM isPart                            MR trace [LEVEL]
   MM label LABEL [,VALUE [LABEL,...    MR warnings

The extra methods for extension writers:

   MR AUTOLOAD                             loadBody
   MM DESTROY                           MR logPriority LEVEL
   MM body [BODY]                       MR logSettings
   MM clone                                moveLocation DISTANCE
  MBM coerce MESSAGE                    MR notImplemented
  MBM diskDelete                           read PARSER
      fileLocation                     MBM readBody PARSER, HEAD [, BO...
   MM head [HEAD]                       MM readFromParser PARSER, [BOD...
   MR inGlobalDestruction               MM readHead PARSER [,CLASS]
   MM isDelayed                         MM statusToLabels
   MM labels                            MM storeBody BODY
   MM labelsToStatus                    MM takeMessageId [STRING]

=head1 METHODS

=over 4

=cut

#-------------------------------------------

=item new OPTIONS

Messages in file-based folders use the following options for creation:

 OPTION        DESCRIBED IN          DEFAULT
 body          Mail::Message         undef
 deleted       Mail::Box::Message    0
 folder        Mail::Box::Message    <required>
 head          Mail::Message         undef
 head_wrap     Mail::Message         72
 log           Mail::Reporter        'WARNINGS'
 messageId     Mail::Message         undef
 modified      Mail::Message         0
 size          Mail::Box::Message    undef
 trace         Mail::Reporter        'WARNINGS'
 trusted       Mail::Message         0

Only for extension writers:

 OPTION        DESCRIBED IN          DEFAULT
 body_type     Mail::Box::Message    <defined by folder>
 field_type    Mail::Message         undef
 head_type     Mail::Message         'Mail::Message::Head::Complete'

=over 4

=item * from_line STRING

The line which begins each message in the file. Some people detest
this line, but this is just how things were invented...

=back

=cut

#-------------------------------------------

sub head(;$$)
{   my $self  = shift;
    return $self->SUPER::head unless @_;

    my ($head, $labels) = @_;
    $self->SUPER::head($head, $labels);
    $self->statusToLabels if $head && !$head->isDelayed;
    $head;
}

#-------------------------------------------

=item fromLine [LINE]

Many people detest file-style folders because they store messages all in
one file, where a line starting with C<From > leads the header.  If we
receive a message from a file-based folder, we store that line.  If we write
to such a file, but there is no such line stored, then we try to generate
one.

If LINE is provided, then the starting line is set to this value.

=cut

sub fromLine(;$)
{   my $self = shift;

    $self->{MBMM_from_line} = shift if @_;
    $self->{MBMM_from_line} ||= $self->head->createFromLine;
}

#-------------------------------------------

=item print [FILEHANDLE]

Write one message to a file handle.  Unmodified messages are taken
from the folder-file where they were stored.  Modified messages
are written to memory.  Specify a FILEHANDLE to write to
(defaults to the selected handle).

=cut

sub print(;$)
{   my $self  = shift;
    my $out   = shift || select;

    $out->print($self->fromLine);
    $self->SUPER::print($out);
    $out->print("\n");
    $self;
}

#-------------------------------------------

sub label(@)
{   my $self   = shift;
    my $return = $self->SUPER::label(@_);
    $self->labelsToStatus if @_ > 1;
    $return;
}

#-------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#-------------------------------------------

=item read PARSER

Read one message from a Mbox folder, including the message separator.
See C<Mail::Message::read()> for more details.

=cut

sub readFromParser($)
{   my ($self, $parser) = @_;
    my ($start, $fromline)  = $parser->readSeparator;
    return unless $fromline;

    $self->{MBMM_from_line} = $fromline;
    $self->{MBMM_begin}     = $start;

    $self->SUPER::readFromParser($parser) or return;

    $self->{MBMM_parser}    = $parser
        if $self->isDelayed;

    $self;
}

#-------------------------------------------

sub clone()
{   my $self  = shift;
    my $clone = $self->SUPER::clone;
    $clone->{MBMM_from_line} = $self->{MBMM_from_line};
    $clone;
}

#-------------------------------------------

sub loadHead() { shift->head }

#-------------------------------------------

=item loadBody

=cut

sub loadBody()
{   my $self     = shift;

    my $body     = $self->body;
#use Carp;
#confess unless defined $body;
    return $body unless $body->isDelayed;

    my $parser   = delete $self->{MBMM_parser};
    my ($begin, $end) = $body->fileLocation;
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

#------------------------------------------

sub coerce($)
{   my ($self, $message) = @_;
    return $message if $message->isa(__PACKAGE__);

    $self->SUPER::coerce($message)->labelsToStatus;
}

#------------------------------------------

=item fileLocation

Returns the location of the whole message including the from-line.  In
LIST context, both begin and end are returned.  In SCALAR context, only
the begin is passed back.

=cut

sub fileLocation()
{   my $self = shift;

    wantarray
     ? ($self->{MBMM_begin}, ($self->body->fileLocation)[1])
     : $self->{MBMM_begin};
}

#------------------------------------------

=item moveLocation DISTANCE

The message is relocated in the file, being moved over DISTANCE bytes.
Setting a new location will update the according information in the header
and body.

=cut

sub moveLocation($)
{   my ($self, $dist) = @_;
    $self->{MBMM_begin} -= $dist;

    $self->head->moveLocation($dist);
    $self->body->moveLocation($dist);
    $self;
}

#-------------------------------------------

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

For support and additional documentation, see http://perl.overmeer.net/mailbox/

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.016.

Copyright (c) 2001-2002 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
