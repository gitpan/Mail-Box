# Copyrights 2001-2009 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.06.

package MailBox::Test::44imap::Definition;
use vars '$VERSION';
$VERSION = '2.087';


sub name     {"Mail::Box::IMAP; imap folders"}
sub critical {0}

sub skip     {
   !defined $ENV{USER} || $ENV{USER} ne 'markov'
}

1;
