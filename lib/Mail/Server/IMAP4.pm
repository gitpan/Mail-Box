
use strict;
use warnings;

package Mail::Server::IMAP4;
use vars '$VERSION';
$VERSION = '2.064';
use base 'Mail::Server';

use Mail::Server::IMAP4::List;
use Mail::Server::IMAP4::Fetch;
use Mail::Server::IMAP4::Search;
use Mail::Transport::IMAP4;


#-------------------------------------------


1;
