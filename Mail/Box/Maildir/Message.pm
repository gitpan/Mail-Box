
package Mail::Box::Maildir::Message;
use vars '$VERSION';
$VERSION = '2.041';
use base 'Mail::Box::Dir::Message';

use strict;
use File::Copy;
use Carp;
use warnings;


sub filename(;$)
{   my $self    = shift;
    my $oldname = $self->SUPER::filename;
    return $oldname unless @_;

    my $newname = shift;
    return $newname if defined $oldname && $oldname eq $newname;

    my ($id, $semantics, $flags)
     = $newname =~ m!(.*?)(?:\:([12])\,([A-Z]*))!
     ? ($1, $2, $3)
     : ($newname, '','');

    my %flags;
    $flags{$_}++ foreach split //, $flags;

    $self->SUPER::label
     ( draft   => ($flags{D} || 0)
     , flagged => ($flags{F} || 0)
     , replied => ($flags{R} || 0)
     , seen    => ($flags{S} || 0)
     );

    $self->SUPER::deleted($flags{T} || 0);

    if(defined $oldname)
    {   move $oldname, $newname
           or confess "Cannot move $oldname to $newname: $!";
    }

    $self->SUPER::filename($newname);
}

#-------------------------------------------


sub guessTimestamp()
{   my $self = shift;
    my $timestamp   = $self->SUPER::guessTimestamp;
    return $timestamp if defined $timestamp;

    $self->filename =~ m/(\d+)/ ? $1 : undef;
}

#-------------------------------------------

sub deleted($)
{   my $self = shift;
    return $self->SUPER::deleted unless @_;

    my $set  = shift;
    $self->SUPER::deleted($set);
    $self->labelsToFilename;
    $set;
}

#-------------------------------------------

sub label(@)
{   my $self   = shift;
    return $self->SUPER::label unless @_;

    my $return = $self->SUPER::label(@_);
    $self->labelsToFilename;
    $return;
}

#-------------------------------------------


sub accept($)
{   my $self   = shift;
    my $old    = $self->filename;

    unless($old =~ m!(.*)/(new|cur|tmp)/([^:]*)(\:[^:]*)?$! )
    {   $self->log(ERROR => "Message $old is not in a Maildir folder.\n");
        return undef;
    }

    return $self if $2 eq 'cur';
    my $new = "$1/cur/$3";

    $self->log(PROGRESS => "Message $old is accepted.\n");
    $self->filename($new);
}

#-------------------------------------------


sub labelsToFilename()
{   my $self   = shift;
    my $labels = $self->labels;
    my $old    = $self->filename;

    my ($folderdir, $set, $oldname)
      = $old =~ m!(.*)/(new|cur|tmp)/([^:]*)(\:[^:]*)?$!;

    my $newflags
      = ($labels->{draft}      ? 'D' : '')    # flags must be alphabetic
      . ($labels->{flagged}    ? 'F' : '')
      . ($labels->{replied}    ? 'R' : '')
      . ($labels->{seen}       ? 'S' : '')
      . ($self->SUPER::deleted ? 'T' : '');

    my $new = File::Spec->catfile($folderdir, $set, "$oldname:2,$newflags");

    if($new ne $old)
    {   unless(move $old, $new)
        {   warn "Cannot rename $old to $new: $!";
            return;
        }
        $self->log(PROGRESS => "Moved $old to $new.");
        $self->SUPER::filename($new);
    }

    $new;
}

#-------------------------------------------

1;
