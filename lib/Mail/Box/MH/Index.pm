
use strict;

package Mail::Box::MH::Index;
use vars '$VERSION';
$VERSION = '2.053';
use base 'Mail::Reporter';

use Mail::Message::Head::Subset;
use Carp;


#-------------------------------------------


sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->{MBMI_filename}  = $args->{filename}
       or croak "No index filename specified.";

    $self->{MBMI_head_wrap} = $args->{head_wrap} || 72;
    $self->{MBMI_head_type}
       = $args->{head_type} || 'Mail::Message::Head::Subset';

    $self;
}

#-------------------------------------------


sub filename() {shift->{MBMI_filename}}

#-------------------------------------------


sub write(@)
{   my $self      = shift;
    my $index     = $self->filename or return $self;
    my $fieldtype = 'Mail::Message::Field';

    # Remove empty index-file.
    unless(@_)
    {   unlink $index;
        return $self;
    }

    my $written    = 0;

    local *INDEX;
    open INDEX, '>', $index or return;

    foreach my $msg (@_)
    {   my $head     = $msg->head;
        next if $head->isDelayed;

        my $filename = $msg->filename;
        $head->setNoRealize($fieldtype->new('X-MailBox-Filename' => $filename));
        $head->setNoRealize($fieldtype->new('X-MailBox-Size'  => -s $filename));
        $head->print(\*INDEX);
        $written++;
    }

    close INDEX;

    unlink $index unless $written;

    $self;
}

#-------------------------------------------


sub read(;$)
{   my $self     = shift;
    my $filename = $self->{MBMI_filename};

    my $parser   = Mail::Box::Parser->new
      ( filename => $filename
      , mode     => 'r'
      ) or return;

    my @options  = ($self->logSettings, wrap_length => $self->{MBMI_head_wrap});
    my $type     = $self->{MBMI_head_type};
    my $index_age= -M $filename;
    my %index;

    while(my $head = $type->new(@options)->read($parser))
    {   my $msgfile = $head->get('x-mailbox-filename');
        my $size    = int $head->get('x-mailbox-size');
        next unless -f $msgfile && -s _ == $size;
        next if defined $index_age && -M _ >= $index_age;

        $index{$msgfile} = $head;
    }

    $parser->stop;

    $self->{MBMI_index} = \%index;
    $self;
}

#-------------------------------------------


sub get($)
{   my ($self, $msgfile) = @_;
    $self->{MBMI_index}{$msgfile};
}

#-------------------------------------------


1;