use strict;
package Mail::Box::Mbox;
our $VERSION = 2.029;  # Part of Mail::Box
use base 'Mail::Box::File';

use Mail::Box::Mbox::Message;

sub type() {'mbox'}

1;
