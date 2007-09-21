# Copyrights 2001-2007 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.02.

package MailBox::Test::44imap::Definition;
use vars '$VERSION';
$VERSION = '2.074';

sub name     {"Mail::Box::IMAP; imap folders"}
sub critical {0}

sub skip     {
   !defined $ENV{USER} || $ENV{USER} ne 'markov'
}

1;
