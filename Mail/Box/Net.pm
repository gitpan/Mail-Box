use strict;
package Mail::Box::Net;
our $VERSION = 2.021;  # Part of Mail::Box

use base 'Mail::Box';

use Mail::Box::Net::Message;

use Mail::Message::Body::Lines;
use Mail::Message::Body::File;
use Mail::Message::Body::Delayed;
use Mail::Message::Body::Multipart;

use Mail::Message::Head;
use Mail::Message::Head::Delayed;

use Carp;
use FileHandle;
use File::Copy;
use File::Spec;
use File::Basename;

sub init($)
{   my ($self, $args)    = @_;

    $args->{body_type} ||= 'Mail::Message::Body::Lines';

    $self->SUPER::init($args);

    $self->{MBN_username} = $args->{username};
    $self->{MBN_password} = $args->{password};
    $self->{MBN_hostname} = $args->{server_name};
    $self->{MBN_port}     = $args->{server_port};

    $self;
}

sub organization() { 'REMOTE' }

1;
