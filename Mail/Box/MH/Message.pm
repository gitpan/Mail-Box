
use strict;
use warnings;

package Mail::Box::MH::Message;
use base 'Mail::Box::Dir::Message';

use File::Copy;
use Carp;

=head1 NAME

Mail::Box::MH::Message - one message in a MH-folder

=head1 CLASS HIERARCHY

 Mail::Box::MH::Message
 is a Mail::Box::Dir::Message
 is a Mail::Box::Message
 is a Mail::Message + ::Construct
 is a Mail::Reporter

=head1 SYNOPSIS

 my $folder = new Mail::Box::MH ...
 my $message = $folder->message(10);

=head1 DESCRIPTION

A C<Mail::Box::MH::Message> represents one message in an MH-folder. Each
message is stored in a separate file.

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Message> (MM), L<Mail::Reporter> (MR), L<Mail::Box::Message> (MBM), L<Mail::Message::Construct> (MMC), L<Mail::Box::Dir::Message> (MBDM).

The general methods for C<Mail::Box::MH::Message> objects:

   MM bcc                               MM label LABEL [,VALUE [LABEL,...
  MMC bounce OPTIONS                    MR log [LEVEL [,STRINGS]]
  MMC build [MESSAGE|BODY], CONTENT     MM messageId
  MMC buildFromBody BODY, HEADERS       MM modified [BOOL]
   MM cc                                   new OPTIONS
  MBM copyTo FOLDER                     MM nrLines
   MM date                              MM parent
   MM decoded OPTIONS                   MM parts
  MBM delete                            MM print [FILEHANDLE]
  MBM deleted [BOOL]                    MM printUndisclosed [FILEHANDLE]
   MM destinations                     MMC read FILEHANDLE|SCALAR|REF-...
   MM encode OPTIONS                   MMC reply OPTIONS
   MR errors                           MMC replyPrelude [STRING|FIELD|...
 MBDM filename [FILENAME]              MMC replySubject STRING
  MBM folder [FOLDER]                   MR report [LEVEL]
  MMC forward OPTIONS                   MR reportAll [LEVEL]
  MMC forwardPostlude                   MM send [MAILER], OPTIONS
  MMC forwardPrelude                   MBM seqnr [INTEGER]
  MMC forwardSubject STRING            MBM shortString
   MM from                              MM size
   MM get FIELD                         MM subject
   MM guessTimestamp                    MM timestamp
   MM isDummy                           MM to
   MM isMultipart                       MM toplevel
   MM isPart                            MR trace [LEVEL]

The extra methods for extension writers:

   MR AUTOLOAD                          MM labelsToStatus
   MM DESTROY                         MBDM loadHead
   MM body [BODY]                       MR logPriority LEVEL
   MM clone                             MR logSettings
   MM coerce MESSAGE                    MR notImplemented
 MBDM create FILENAME                 MBDM parser
  MBM diskDelete                       MBM readBody PARSER, HEAD [, BO...
   MM head [HEAD]                       MM readFromParser PARSER, [BOD...
   MR inGlobalDestruction               MM readHead PARSER [,CLASS]
   MM isDelayed                         MM statusToLabels
   MM labels                            MM storeBody BODY

=head1 METHODS

=over 4

=cut

#-------------------------------------------

=item new OPTIONS

Messages in directory-based folders use the following options:

 OPTION      DESCRIBED IN             DEFAULT
 body        Mail::Message            undef
 deleted     Mail::Box::Message       0
 filename    Mail::Box::Dir::Message  undef
 folder      Mail::Box::Message       <required>
 head        Mail::Message            undef
 head_wrap   Mail::Message            undef
 log         Mail::Reporter           'WARNINGS'
 messageId   Mail::Message            undef
 modified    Mail::Message            0
 size        Mail::Box::Message       undef
 trace       Mail::Reporter           'WARNINGS'
 trusted     Mail::Message            0

Only for extension writers:

 OPTION      DESCRIBED IN             DEFAULT
 body_type   Mail::Box::Message       <not used>
 field_type  Mail::Message            undef
 head_type   Mail::Message            'Mail::Message::Head::Complete'

=cut

#-------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

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

This code is beta, version 2.013.

Copyright (c) 2001-2002 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
