
use strict;
package Mail::Box::Mbox::Message;
use vars '$VERSION';
$VERSION = '2.050';
use base 'Mail::Box::File::Message';


#-------------------------------------------

sub head(;$$)
{   my $self  = shift;
    return $self->SUPER::head unless @_;

    my ($head, $labels) = @_;
    $self->SUPER::head($head, $labels);

    $self->statusToLabels if $head && !$head->isDelayed;
    $head;
}

#-------------------------------------------

sub label(@)
{   my $self   = shift;
    $self->loadHead;    # be sure the status fields have been read
    my $return = $self->SUPER::label(@_);
    $self->labelsToStatus if @_ > 1;
    $return;
}

#-------------------------------------------

sub labels(@)
{   my $self   = shift;
    $self->loadHead;    # be sure the status fields have been read
    $self->SUPER::labels(@_);
}

#------------------------------------------


1;
