# Copyrights 2001-2007 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.02.

use strict;
use warnings;

package Mail::Box::Maildir::Message;
use vars '$VERSION';
$VERSION = '2.074';
use base 'Mail::Box::Dir::Message';

use File::Copy;


sub filename(;$)
{   my $self    = shift;
    my $oldname = $self->SUPER::filename();
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
     , deleted => ($flags{T} || 0)

     , passed  => ($flags{P} || 0)   # uncommon
     );

    if(defined $oldname && ! move $oldname, $newname)
    {   $self->log(ERROR => "Cannot move $oldname to $newname: $!");
        return undef;
    }

    $self->SUPER::filename($newname);
}

#-------------------------------------------


sub guessTimestamp()
{   my $self = shift;
    my $timestamp   = $self->SUPER::guessTimestamp;
    return $timestamp if defined $timestamp;

    $self->filename =~ m/^(\d+)/ ? $1 : undef;
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


sub labelsToFilename()
{   my $self   = shift;
    my $labels = $self->labels;
    my $old    = $self->filename;

    my ($folderdir, $set, $oldname)
      = $old =~ m!(.*)/(new|cur|tmp)/([^:]*)(\:[^:]*)?$!;

    my $newflags    # alphabeticly ordered!
      = ($labels->{draft}   ? 'D' : '')
      . ($labels->{flagged} ? 'F' : '')
      . ($labels->{passed}  ? 'P' : '')
      . ($labels->{replied} ? 'R' : '')
      . ($labels->{seen}    ? 'S' : '')
      . ($labels->{deleted} ? 'T' : '');

    my $newset = $labels->{accepted} ? 'cur' : 'new';
    if($set ne $newset)
    {   my $folder = $self->folder;
        $folder->modified(1) if defined $folder;
    }

    my $new = File::Spec->catfile($folderdir, $newset, "$oldname:2,$newflags");

    if($new ne $old)
    {   unless(move $old, $new)
        {   $self->log(ERROR => "Cannot rename $old to $new: $!");
            return;
        }
        $self->log(PROGRESS => "Moved $old to $new.");
        $self->SUPER::filename($new);
    }

    $new;
}

#-------------------------------------------


sub accept(;$)
{   my $self   = shift;
    my $accept = @_ ? shift : 1;
    $self->label(accepted => $accept);
}

#-------------------------------------------


1;
