# Copyrights 2001-2008 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.04.

use strict;

package Mail::Box::Locker::DotLock;
use vars '$VERSION';
$VERSION = '2.082';

use base 'Mail::Box::Locker';

use IO::File;
use File::Spec;
use Errno      qw/EEXIST/;
use Carp;


sub init($)
{   my ($self, $args) = @_;

    unless($args->{file})
    {   my $folder = $args->{folder}
           or confess;

        my $org    = $folder->organization;

        $args->{file}
         = $org eq 'FILE'      ? $folder->filename . '.lock'
         : $org eq 'DIRECTORY' ? File::Spec->catfile($folder->directory,'.lock')
         : croak "Need lock file name for DotLock.";
    }

    $self->SUPER::init($args);
}

#-------------------------------------------

sub name() {'DOTLOCK'}

#-------------------------------------------

sub _try_lock($)
{   my ($self, $lockfile) = @_;
    return if -e $lockfile;

    my $flags    = $^O eq 'MSWin32'
                 ?  O_CREAT|O_EXCL|O_WRONLY
                 :  O_CREAT|O_EXCL|O_WRONLY|O_NONBLOCK;

    my $lock = IO::File->new($lockfile, $flags, 0600);
    if($lock)
    {   close $lock;
        return 1;
    }

    if($! != EEXIST)
    {   $self->log(ERROR => "lockfile $lockfile can never be created: $!");
        return 1;
    }
}

#-------------------------------------------


sub unlock()
{   my $self = shift;
    $self->{MBL_has_lock}
        or return $self;

    my $lock = $self->filename;

    unlink $lock
        or $self->log(WARNING => "Couldn't remove lockfile $lock: $!");

    delete $self->{MBL_has_lock};
    $self;
}

#-------------------------------------------


sub lock()
{   my $self   = shift;

    my $lockfile = $self->filename;
    if($self->hasLock)
    {   $self->log(WARNING => "Folder already locked with file $lockfile");
        return 1;
    }

    my $end      = $self->{MBL_timeout} eq 'NOTIMEOUT' ? -1
                 : $self->{MBL_timeout};
    my $expire   = $self->{MBL_expires}/86400;  # in days for -A

    while(1)
    {
        return $self->{MBL_has_lock} = 1
           if $self->_try_lock($lockfile);

        if(-e $lockfile && -A $lockfile > $expire)
        {
            if(unlink $lockfile)
            {   $self->log(WARNING => "Removed expired lockfile $lockfile");
                redo;
            }
            else
            {   $self->log(ERROR =>
                   "Failed to remove expired lockfile $lockfile: $!");
                last;
            }
        }

        last unless --$end;
        sleep 1;
    }

    return 0;
}

#-------------------------------------------

sub isLocked() { -e shift->filename }

#-------------------------------------------

1;

