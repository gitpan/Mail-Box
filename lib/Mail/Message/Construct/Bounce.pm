
use strict;

package Mail::Message;
use vars '$VERSION';
$VERSION = '2.062';

use Mail::Message::Head::Complete;
use Mail::Message::Field;
use Carp         qw/croak/;


sub bounce(@)
{   my $self   = shift;
    my $bounce = $self->clone;
    my $head   = $bounce->head;

    if(@_==1 && ref $_[0] && $_[0]->isa('Mail::Message::Head::ResentGroup' ))
    {    $head->addResentGroup(shift);
         return $bounce;
    }

    my @rgs    = $head->resentGroups;
    my $rg     = $rgs[0];

    if(defined $rg)
    {   $rg->delete;     # Remove group to re-add it later: otherwise
        while(@_)        #   field order in header would be disturbed.
        {   my $field = shift;
            ref $field ? $rg->set($field) : $rg->set($field, shift);
        }
    }
    elsif(@_)
    {   $rg = Mail::Message::Head::ResentGroup->new(@_);
    }
    else
    {   croak "ERROR: bounce requires To, Cc, or Bcc";
    }
 
    #
    # Add some nice extra fields.
    #

    $rg->set(Date => Mail::Message::Field->toDate)
        unless defined $rg->date;

    unless(defined $rg->messageId)
    {   my $msgid = $head->createMessageId;
        $rg->set('Message-ID' => "<$msgid>");
    }

    $head->addResentGroup($rg);

    #
    # Flag action to original message
    #

    $self->label(passed => 1);    # used by some maildir clients

    $bounce;
}

1;
