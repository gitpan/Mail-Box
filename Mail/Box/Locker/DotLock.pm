use strict;

package Mail::Box::Locker::DotLock;
our $VERSION = 2.028;  # Part of Mail::Box
use base 'Mail::Box::Locker';

use IO::File;
use Carp;

sub name() {'DOTLOCK'}

sub _try_lock($)
{   my ($self, $lockfile) = @_;
    return if -e $lockfile;

    my $flags    = $^O eq 'MSWin32'
                 ?  O_CREAT|O_EXCL|O_WRONLY
                 :  O_CREAT|O_EXCL|O_WRONLY|O_NONBLOCK;

    my $lock     = IO::File->new($lockfile, $flags, 0600)
        or return 0;

    close $lock;
    1;
}

sub unlock()
{   my $self = shift;
    return $self unless $self->{MBL_has_lock};

    my $lock = $self->filename;

    unlink $lock
        or warn "Couldn't remove lockfile $lock: $!\n";

    delete $self->{MBL_has_lock};
    $self;
}

sub lock()
{   my $self   = shift;
    return 1 if $self->hasLock;

    my $lockfile = $self->filename;
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
            {   warn "Removed expired lockfile $lockfile.\n";
                redo;
            }
            else
            {   warn "Failed to remove expired lockfile $lockfile: $!\n";
                last;
            }
        }

        last unless --$end;
        sleep 1;
    }

    return 0;
}

sub isLocked() { -e shift->filename }

1;
