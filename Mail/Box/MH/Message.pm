
use strict;
use warnings;

package Mail::Box::MH::Message;
use vars '$VERSION';
$VERSION = '2.042';
use base 'Mail::Box::Dir::Message';

use File::Copy;
use Carp;


# implementation in Mail::Box::Message.  It is only "helpful" text.

1;
