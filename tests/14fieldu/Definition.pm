# Copyrights 2001-2007 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.02.

package MailBox::Test::14fieldu::Definition;
use vars '$VERSION';
$VERSION = '2.075';

sub name     {"Mail::Message::Field::Full; unicode fields"}
sub critical {0}

sub skip
{
   return "Requires module Encode, which requires at least Perl 5.7.3"
       if $] < 5.007003;

   eval "require Encode";
   return "Module Encode is not installed or has errors." if $@;

   undef;
}

1;
