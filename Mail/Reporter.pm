use strict;
use warnings;

package Mail::Reporter;
our $VERSION = 2.028;  # Part of Mail::Box

use Carp;

# synchronize this with C code in Mail::Box::Parser.
my @levelname = (undef, qw(DEBUG NOTICE PROGRESS WARNING ERROR NONE INTERNAL));

my %levelprio = (ERRORS => 5, WARNINGS => 4, NOTICES => 2);
for(my $l = 1; $l < @levelname; $l++)
{   $levelprio{$levelname[$l]} = $l;
    $levelprio{$l} = $l;
}

sub new(@) {my $class = shift; (bless {}, $class)->init({@_}) }

my $default_log   = $levelprio{WARNINGS};
my $default_trace = $levelprio{WARNINGS};

sub init($)
{   my ($self, $args) = @_;
    $self->{MR_log}   = $levelprio{$args->{log}   || $default_log};
    $self->{MR_trace} = $levelprio{$args->{trace} || $default_trace};
    $self;
}

sub defaultTrace(;$$)
{   my $self = shift;
    return ($default_log, $default_trace) unless @_;

    ($default_log, $default_trace) = @_==1 ? ($_[0], $_[0]) : @_;
}

sub trace(;$)
{   my $self = shift;
    return $levelname[$self->{MR_trace}] unless @_;

    my $level = shift;
    my $prio  = $levelprio{$level}
        or croak "Unknown trace-level $level.";

    $self->{MR_trace} = $prio;
}

# Implementation detail: the C code avoids calls back to Perl by
# checking the trace-level itself.  In the perl code of this module
# however, just always call the log() method, and let it check
# whether or not to display it.

sub log(;$@)
{   my $thing = shift;

    if(ref $thing)   # instance call
    {   return $levelname[$thing->{MR_log}] unless @_;

        my $level = shift;
        my $prio  = $levelprio{$level}
            or croak "Unknown log-level $level.";

        return $thing->{MR_log} = $prio unless @_;

        my $text    = join '', @_;
        $text      .= "\n" unless (substr $text, -1) eq "\n";

        warn "$level: $text"
            if $prio >= $thing->{MR_trace};

        push @{$thing->{MR_report}[$prio]}, $text
            if $prio >= $thing->{MR_log};
    }
    else             # class method
    {   my $level = shift;
        my $prio  = $levelprio{$level}
            or croak "Unknown log-level $level.";

        return $thing unless $prio >= $default_trace;

        my $text    = join '', @_;
        $text      .= "\n" unless (substr $text, -1) eq "\n";

        warn "$level: $text";
    }

    $thing;
}

sub report(;$)
{   my $self    = shift;
    my $reports = $self->{MR_report} || return ();

    if(@_)
    {   my $level = shift;
        my $prio  = $levelprio{$level}
            or croak "Unknown report level $level.";

        return $reports->[$prio] ? @{$reports->[$prio]} : ();
    }

    my @reports;
    for(my $prio = 1; $prio < @$reports; $prio++)
    {   next unless $reports->[$prio];
        my $level = $levelname[$prio];
        push @reports, map { [ $level, $_ ] } @{$reports->[$prio]};
    }

    @reports;
}

sub reportAll(;$)
{   my $self = shift;
    map { [ $self, @$_ ] } $self->report(@_);
}

sub errors(@)   {shift->report('ERRORS')}

sub warnings(@) {shift->report('WARNINGS')}

sub notImplemented(@)
{   my $self    = shift;
    my $package = ref $self || $self;
    my $sub     = (caller 1)[3];

    $self->log(INTERNAL => "$package does not implement $sub.");
    confess "Please warn the author, this shouldn't happen.";
}

sub logPriority($) { $levelprio{$_[1]} }

sub logSettings()
{  my $self = shift;
   (log => $self->{MR_log}, trace => $self->{MR_trace});
}

my $global_destruction;
END {$global_destruction++}
sub inGlobalDestruction() {$global_destruction}

sub DESTROY {shift}

sub AUTOLOAD(@)
{   my $self  = shift;
    our $AUTOLOAD;
    my $class = ref $self;
    (my $method = $AUTOLOAD) =~ s/^$class\:\://;

    $Carp::MaxArgLen=20;
    confess "Method $method() is not defined for a $class.\n";
}

1;
