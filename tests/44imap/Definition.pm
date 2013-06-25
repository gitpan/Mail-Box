# Copyrights 2001-2013 by [Mark Overmeer].
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 2.01.

package MailBox::Test::44imap::Definition;
use vars '$VERSION';
$VERSION = '2.108';


sub name     {"Mail::Box::IMAP; imap folders"}
sub critical {0}

sub skip     {
   !defined $ENV{USER} || $ENV{USER} ne 'markov'
}

1;
