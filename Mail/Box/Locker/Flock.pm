use strict;

package Mail::Box::Locker::Flock;
our $VERSION = 2.028;  # Part of Mail::Box
use base 'Mail::Box::Locker';

use Fcntl         qw/:DEFAULT :flock/;
use IO::File;
use Errno         qw/EAGAIN/;
use FileHandle;

sub name() {'FLOCK'}

sub _try_lock($)
{   my ($self, $file) = @_;
    flock $file, LOCK_EX|LOCK_NB;
}

sub _unlock($)
{   my ($self, $file) = @_;
    flock $file, LOCK_UN;
    delete $self->{MBL_has_lock};
    $self;
}

# 'r+' is require under Solaris and AIX, other OSes are satisfied with 'r'.
my $lockfile_access_mode = ($^O eq 'solaris' || $^O eq 'aix') ? 'r+' : 'r';

sub lock()
{   my $self  = shift;
    return 1 if $self->hasLock;

    my $filename = $self->filename;

    my $file   = FileHandle->new($filename, $lockfile_access_mode);
    unless($file)
    {   $self->log(ERROR => "Unable to open lockfile $filename");
        return 0;
    }

    my $end = $self->{MBL_timeout} eq 'NOTIMEOUT' ? -1 : $self->{MBL_timeout};

    while(1)
    {   if($self->_try_lock($file))
        {   $self->{MBL_has_lock}    = 1;
            $self->{MBLF_filehandle} = $file;
            return 1;
        }

        if($! != EAGAIN)
        {   $self->log(ERROR =>
                  "Will never get a lock at ".$self->{MBL_folder}->name.": $!");
            last;
        }

        last unless --$end;
        sleep 1;
    }

    return 0;
}

sub isLocked()
{   my $self     = shift;
    my $filename = $self->filename;

    my $file     = FileHandle->new($filename, $lockfile_access_mode);
    unless($file)
    {   $self->log(ERROR => "Unable to open lockfile $filename");
        return 0;
    }

    $self->_try_lock($file) or return 0;
    $self->_unlock($file);
    $file->close;

    1;
}

sub unlock()
{   my $self = shift;

    $self->_unlock(delete $self->{MBLF_filehandle})
       if $self->hasLock;

    $self;
}

1;
