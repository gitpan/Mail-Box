use strict;
use warnings;

package Mail::Box::MH::Message;
our $VERSION = 2.035;  # Part of Mail::Box
use base 'Mail::Box::Dir::Message';

use File::Copy;
use Carp;

1;
