
use strict;
use warnings;

package Mail::Box::MH::Message;
use vars '$VERSION';
$VERSION = '2.053';
use base 'Mail::Box::Dir::Message';

use File::Copy;
use Carp;


1;