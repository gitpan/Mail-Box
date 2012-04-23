# Copyrights 2001-2012 by [Mark Overmeer].
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 2.00.

package MailBox::Test::80msgconv::Definition;
use vars '$VERSION';
$VERSION = '2.104';


sub name     {"Mail::Message::Convert; message conversions"}
sub critical {0}

sub skip
{   eval "require Mail::Internet";
    my $mailtools = !$@;

    eval "require MIME::Entity";
    my $mime = !$@;

    return "Neighter MailTools nor MIME::Tools are installed"
       unless $mailtools || $mime;

    undef;
}

1;
