
package Mail::Message::Head::SpamGroup;
use vars '$VERSION';
$VERSION = '2.051';
use base 'Mail::Message::Head::FieldGroup';

use strict;
use warnings;


#------------------------------------------

my @implemented = qw/SpamAssassin Habeas-SWE MailScanner/;

sub implementedTypes() { @implemented }

#------------------------------------------


sub from($@)
{  my ($class, $from, %args) = @_;
   my $head  = $from->isa('Mail::Message::Head') ? $from : $from->head;
   my ($self, @detected);

   my @types = defined $args{types} ? @{$args{types}}
             :                        $class->implementedTypes;

   foreach my $type (@types)
   {   $self = $class->new(head => $head) unless defined $self;
       next unless $self->collectFields($type);

       my ($software, $version, $spam);
       if($type eq 'SpamAssassin')
       {   if(my $assassin = $head->get('X-Spam-Checker-Version'))  
           {   # SpamAssassin combine version and subversion.
               ($software, $version) = $assassin =~ m/^(.*)\s+(.*?)\s*$/;
           }

           if(my $f = $head->get('X-Spam-Flag') || $head->get('X-Spam-Status'))
           {   $spam = $f =~ m/yes/i;
           }
       }
       elsif($type eq 'Habeas-SWE')
       {   ; # no version information, as far as I know
           $spam = not $self->habeasSweFieldsCorrect;
       }
       elsif($type eq 'MailScanner')
       {   ; # no version information, as far as I know
           my $subject = $head->get('subject');
           $spam = $subject =~ m/^\{ (?:spam|virus)/xi;
       }
 
       $self->detected($type, $software, $version);
       $self->spamDetected($spam);

       push @detected, $self;
       undef $self;             # create a new one
   }

   @detected;
}

#------------------------------------------

my $spam_assassin_names = qr/^X-Spam-/i;
my $habeas_swe_names    = qr/^X-Habeas-SWE/i;
my $mailscanner_names   = qr/^X-MailScanner/i;

sub collectFields($)
{   my ($self, $set) = @_;
    my $scan = $set eq 'SpamAssassin' ? $spam_assassin_names
             : $set eq 'Habeas-SWE'   ? $habeas_swe_names
             : $set eq 'MailScanner'  ? $mailscanner_names
             : die "No spam set $set.";

    my @names = map { $_->name } $self->head->grepNames($scan);
    return () unless @names;

    $self->addFields(@names);
    @names;
}

#------------------------------------------


sub isSpamGroupFieldName($)
{  local $_ = $_[1];
    my $about_spam = (   $_ =~ $spam_assassin_names
                      || $_ =~ $habeas_swe_names
                      || $_ =~ $mailscanner_names
                     );
    $about_spam;
}

#------------------------------------------


my @habeas_lines =
( 'winter into spring', 'brightly anticipated', 'like Habeas SWE (tm)'
, 'Copyright 2002 Habeas (tm)'
, 'Sender Warranted Email (SWE) (tm). The sender of this'
, 'email in exchange for a license for this Habeas'
, 'warrant mark warrants that this is a Habeas Compliant'
, 'Message (HCM) and not spam. Please report use of this'
, 'mark in spam to <http://www.habeas.com/report/>.'
);

sub habeasSweFieldsCorrect(;$)
{   my $self;

    if(@_ > 1)
    {   my ($class, $thing) = @_;
        my $head = $thing->isa('Mail::Message::Head') ? $thing : $thing->head;
        $self    = $head->spamGroups('Habeas-SWE') or return;
    }
    else
    {   $self = shift;
        my $type = $self->type;
        return unless defined $type && $type eq 'Habeas-SWE';
    }

    my $head     = $self->head;
    return if $self->fields != @habeas_lines;

    for(my $nr=1; $nr <= $#habeas_lines; $nr++)
    {   my $f = $head->get("X-Habeas-SWE-$nr") or return;
        return if $f->unfoldedBody ne $habeas_lines[$nr-1];
    }

    1;
}

#------------------------------------------


sub spamDetected(;$)
{   my $self = shift;
    @_? ($self->{MMFS_spam} = shift) : $self->{MMFS_spam};
}

#------------------------------------------


1;
