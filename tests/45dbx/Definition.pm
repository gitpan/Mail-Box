# Copyrights 2001-2008 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.05.

package MailBox::Test::45dbx::Definition;
use vars '$VERSION';
$VERSION = '2.083';


sub name     {"Mail::Box::Dbx; Outlook Express folders"}
sub critical {0}

sub skip
{
    eval "require Mail::Transport::Dbx";
    return "Mail::Transport::Dbx is not installed or gives errors." if $@;

    undef;
}

1;
