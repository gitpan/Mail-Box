# Copyrights 2001-2009 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.06.

use strict;
use warnings;

package Mail::Server::IMAP4;
use vars '$VERSION';
$VERSION = '2.090';

use base 'Mail::Server';

use Mail::Server::IMAP4::List;
use Mail::Server::IMAP4::Fetch;
use Mail::Server::IMAP4::Search;
use Mail::Transport::IMAP4;


#-------------------------------------------


1;
