use strict;

package Mail::Box::Locker;
our $VERSION = 2.028;  # Part of Mail::Box
use base 'Mail::Reporter';

use Carp;
use File::Spec;
use Scalar::Util 'weaken';

my %lockers =
  ( DOTLOCK => __PACKAGE__ .'::DotLock'
  , FLOCK   => __PACKAGE__ .'::Flock'
  , MULTI   => __PACKAGE__ .'::Multi'
  , NFS     => __PACKAGE__ .'::NFS'
  , NONE    => __PACKAGE__
  , POSIX   => __PACKAGE__ .'::POSIX'
  );

sub new(@)
{   my $class  = shift;

    return $class->SUPER::new(@_)
        unless $class eq __PACKAGE__;

    my %args   = @_;
    my $method = defined $args{method} ? uc $args{method} : 'DOTLOCK';
    my $create = $lockers{$method} || $args{$method};

    local $" = ' or ';
    confess "No locking method $method defined: use @{[ keys %lockers ]}"
        unless $create;

    # compile the locking module (if needed)
    eval "require $create";
    confess $@ if $@;

    $create->SUPER::new(%args);
}

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);

    $self->{MBL_folder}   = $args->{folder}
        or croak "No folder specified to be locked.\n";

    weaken($self->{MBL_folder});

    $self->{MBL_expires}  = $args->{expires}   || 3600;  # one hour
    $self->{MBL_timeout}  = $args->{timeout}   || 10;    # ten secs
    $self->{MBL_filename} = $args->{file};
    $self->{MBL_has_lock} = 0;

    $self;
}

sub name {shift->notImplemented}

sub lockMethod($$$$)
{   confess "Method removed: use inheritance to implement own method."
}

sub filename($)
{   my $self   = shift;
    return $self->{MBL_filename} if defined $self->{MBL_filename};

    my $folder = $self->{MBL_folder};
    my $org    = $folder->organization;
    $self->{MBL_filename}
        = $org eq 'FILE'      ? $folder->filename . '.lock'
        : $org eq 'DIRECTORY' ? File::Spec->catfile($folder->directory, '.lock')
        : croak "Need lock-file name.";
}

sub DESTROY()
{   my $self = shift;
    $self->unlock if $self->hasLock;
    $self->SUPER::DESTROY;
    $self;
}

sub lock($) { shift->{MBL_has_lock} = 1 }

sub isLocked($) {0}

sub hasLock() {shift->{MBL_has_lock} }

# implementation hazard: the unlock must be self-reliant, without
# help by the folder, because it may be called at global destruction
# after the folder has been removed.

sub unlock() { shift->{MBL_has_lock} = 0 }

1;
