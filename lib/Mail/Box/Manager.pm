use strict;
use warnings;

package Mail::Box::Manager;
use vars '$VERSION';
$VERSION = '2.046';
use base 'Mail::Reporter';

use Mail::Box;

use Carp;
use List::Util   'first';
use Scalar::Util 'weaken';

#-------------------------------------------


my @basic_folder_types =
  ( [ mbox    => 'Mail::Box::Mbox'    ]
  , [ mh      => 'Mail::Box::MH'      ]
  , [ maildir => 'Mail::Box::Maildir' ]
  , [ pop     => 'Mail::Box::POP3'    ]
  , [ pop3    => 'Mail::Box::POP3'    ]
  );

my @managers;  # usually only one, but there may be more around :(

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    # Register all folder-types.  There may be some added later.

    my @types;
    if(exists $args->{folder_types})
    {   @types = ref $args->{folder_types}[0]
               ? @{$args->{folder_types}}
               : $args->{folder_types};
    }

    $self->{MBM_folder_types} = [];
    $self->registerType(@$_) foreach @types, reverse @basic_folder_types;

    $self->{MBM_default_type} = $args->{default_folder_type};

    # Inventory on existing folder-directories.

    $self->{MBM_folderdirs} = [ '.' ];
    if(exists $args->{folderdir})
    {   my @dirs = $args->{folderdir};
        @dirs = @{$dirs[0]} if ref $dirs[0];
        push @{$self->{MBM_folderdirs}}, @dirs;
    }

    if(exists $args->{folderdirs})
    {   my @dirs = $args->{folderdirs};
        @dirs = @{$dirs[0]} if ref $dirs[0];
        push @{$self->{MBM_folderdirs}}, @dirs;
    }

    $self->{MBM_folders} = [];
    $self->{MBM_threads} = [];

    push @managers, $self;
    weaken $managers[-1];

    $self;
}

#-------------------------------------------


sub registerType($$@)
{   my ($self, $name, $class, @options) = @_;
    unshift @{$self->{MBM_folder_types}}, [$name, $class, @options];
    $self;
}

#-------------------------------------------


sub folderTypes()
{   my $self = shift;
    my %uniq;
    $uniq{$_->[0]}++ foreach @{$self->{MBM_folder_types}};
    sort keys %uniq;
}


#-------------------------------------------


sub open(@)
{   my $self = shift;
    my $name = @_ % 2 ? shift : undef;
    my %args = @_;

    $name    = defined $args{folder} ? $args{folder} : $ENV{MAIL}
        unless defined $name;

    if($name =~ m/^(\w+)\:/ && grep { $_ eq $1 } $self->folderTypes)
    {   # Complicated folder URL
        my %decoded = $self->decodeFolderURL($name);
        if(keys %decoded)
        {   # accept decoded info
            @args{keys %decoded} = values %decoded;
        }
        else
        {   $self->log(ERROR => "Illegal folder URL '$name'.");
            return;
        }
    }
    else
    {   # Simple folder name
        $args{folder} = $name;
    }

    unless(defined $name && length $name)
    {   $self->log(ERROR => "No foldername specified to open.\n");
        return undef;
    }
        
    $args{folderdir} ||= $self->{MBM_folderdirs}->[0]
        if $self->{MBM_folderdirs};

    $args{access} ||= 'r';

    if($args{create} && $args{access} !~ m/w|a/)
    {   $self->log(WARNING
           => "Will never create a folder $name without having write access.");
        undef $args{create};
    }

    # Do not open twice.
    if(my $folder = $self->isOpenFolder($name))
    {   $self->log(NOTICE => "Folder $name is already open.\n");
        return $folder;
    }

    #
    # Which folder type do we need?
    #

    my ($folder_type, $class, @defaults);
    if(my $type = $args{type})
    {   # User-specified foldertype prevails.
        foreach (@{$self->{MBM_folder_types}})
        {   (my $abbrev, $class, @defaults) = @$_;

            if($type eq $abbrev || $type eq $class)
            {   $folder_type = $abbrev;
                last;
            }
        }

        $self->log(ERROR => "Folder type $type is unknown, using autodetect.")
            unless $folder_type;
    }

    unless($folder_type)
    {   # Try to autodetect foldertype.
        foreach (@{$self->{MBM_folder_types}})
        {   (my $abbrev, $class, @defaults) = @$_;

            eval "require $class";
            next if $@;

            if($class->foundIn($name, @defaults, %args))
            {   $folder_type = $abbrev;
                last;
            }
        }
     }

    unless($folder_type)
    {   # Use specified default
        if(my $type = $self->{MBM_default_type})
        {   foreach (@{$self->{MBM_folder_types}})
            {   (my $abbrev, $class, @defaults) = @$_;
                if($type eq $abbrev || $type eq $class)
                {   $folder_type = $abbrev;
                    last;
                }
            }
        }
    }

    unless($folder_type)
    {   # use first type (last defined)
        ($folder_type, $class, @defaults) = @{$self->{MBM_folder_types}[0]};
    }
    
    #
    # Try to open the folder
    #

    eval "require $class";
    croak if $@;

    push @defaults, manager => $self;
    my $folder = $class->new(@defaults, %args);

    unless(defined $folder)
    {   $self->log(WARNING =>"Folder does not exist, failed opening $folder_type folder $name.");
        return;
    }

    $self->log(PROGRESS => "Opened folder $name ($folder_type).");
    push @{$self->{MBM_folders}}, $folder;
    $folder;
}

#-------------------------------------------


sub openFolders() { @{shift->{MBM_folders}} }

#-------------------------------------------


sub isOpenFolder($)
{   my ($self, $name) = @_;
    first {$name eq $_->name} $self->openFolders;
}

#-------------------------------------------


sub close($@)
{   my ($self, $folder, @options) = @_;
    return unless $folder;

    my $name      = $folder->name;
    my @remaining = grep {$name ne $_->name} @{$self->{MBM_folders}};

    # folder opening failed:
    return if @{$self->{MBM_folders}} == @remaining;

    $self->{MBM_folders} = [ @remaining ];
    $_->removeFolder($folder) foreach @{$self->{MBM_threads}};

    $folder->close(close_by_manager => 1, @options);
    $self;
}

#-------------------------------------------


sub closeAllFolders(@)
{   my ($self, @options) = @_;
    $_->close(@options) foreach $self->openFolders;
    $self;
}

END {map {defined $_ && $_->closeAllFolders} @managers}

#-------------------------------------------


sub delete($@)
{   my ($self, $name, @options) = @_;
    my $folder = $self->open(folder => $name, @options) or return;
    $folder->delete;
}

#-------------------------------------------


sub appendMessage(@)
{   my $self     = shift;
    my @appended = $self->appendMessages(@_);
    wantarray ? @appended : $appended[0];
}

sub appendMessages(@)
{   my $self = shift;
    my $folder;
    $folder  = shift if !ref $_[0] || $_[0]->isa('Mail::Box');

    my @messages;
    push @messages, shift while @_ && ref $_[0];

    my %options = @_;
    $folder ||= $options{folder};

    # Try to resolve filenames into opened-files.
    $folder = $self->isOpenFolder($folder) || $folder
        unless ref $folder;

    if(ref $folder)
    {   # An open file.
        unless($folder->isa('Mail::Box'))
        {   $self->log(ERROR =>
                "Folder $folder is not a Mail::Box; cannot add a message.\n");
            return ();
        }

        foreach (@messages)
        {   next unless $_->isa('Mail::Box::Message') && $_->folder;
            $self->log(WARNING =>
               "Use moveMessage() or copyMessage() to move between open folders.");
        }

        return $folder->addMessages(@messages);
    }

    # Not an open file.
    # Try to autodetect the folder-type and then add the message.

    my ($name, $class, @gen_options, $found);

    foreach (@{$self->{MBM_folder_types}})
    {   ($name, $class, @gen_options) = @$_;
        eval "require $class";
        next if $@;

        if($class->foundIn($folder, @gen_options, access => 'a'))
        {   $found++;
            last;
        }
    }
 
    # The folder was not found at all, so we take the default folder-type.
    my $type = $self->{MBM_default_type};
    if(!$found && $type)
    {   foreach (@{$self->{MBM_folder_types}})
        {   ($name, $class, @gen_options) = @$_;
            if($type eq $name || $type eq $class)
            {   $found++;
                last;
            }
        }
    }

    # Even the default foldertype was not found (or nor defined).
    ($name, $class, @gen_options) = @{$self->{MBM_folder_types}[0]}
        unless $found;

    $class->appendMessages
      ( type     => $name
      , messages => \@messages
      , @gen_options
      , %options
      , folder   => $folder
      );
}

#-------------------------------------------


sub copyMessage(@)
{   my $self   = shift;
    my $folder;
    $folder    = shift if !ref $_[0] || $_[0]->isa('Mail::Box');

    my @messages;
    while(@_ && ref $_[0])
    {   my $message = shift;
        $self->log(ERROR =>
            "Use appendMessage() to add messages which are not in a folder.")
                unless $message->isa('Mail::Box::Message');
        push @messages, $message;
    }

    my %options = @_;
    $folder ||= $options{folder};

    # Try to resolve filenames into opened-files.
    $folder = $self->isOpenFolder($folder) || $folder
        unless ref $folder;

    my @coerced
     = ref $folder
     ? map {$_->copyTo($folder)} @messages
     : $self->appendMessages(@messages, %options, folder => $folder);

    # hidden option, do not use it: it's designed to optimize moveMessage
    if($options{_delete})
    {   $_->delete foreach @messages;
    }

    @coerced;
}

#-------------------------------------------


sub moveMessage(@)
{   my $self = shift;
    $self->copyMessage(@_, _delete => 1);
}

#-------------------------------------------


#-------------------------------------------


sub threads(@)
{   my $self    = shift;
    my @folders;
    push @folders, shift
       while @_ && ref $_[0] && $_[0]->isa('Mail::Box');
    my %args    = @_;

    my $base    = 'Mail::Box::Thread::Manager';
    my $type    = $args{threader_type} || $base;

    my $folders = delete $args{folder} || delete $args{folders};
    push @folders
     , ( !$folders               ? ()
       : ref $folders eq 'ARRAY' ? @$folders
       :                           $folders
       );

    $self->log(INTERNAL => "No folders specified.\n")
       unless @folders;

    my $threads;
    if(ref $type)
    {   # Already prepared object.
        $self->log(INTERNAL => "You need to pass a $base derived")
            unless $type->isa($base);
        $threads = $type;
    }
    else
    {   # Create an object.  The code is compiled, which safes us the
        # need to compile Mail::Box::Thread::Manager when no threads are needed.
        eval "require $type";
        $self->log(INTERNAL => "Unusable threader $type: $@") if $@;
        $self->log(INTERNAL => "You need to pass a $base derived")
            unless $type->isa($base);

        $threads = $type->new(manager => $self, %args);
    }

    $threads->includeFolder($_) foreach @folders;
    push @{$self->{MBM_threads}}, $threads;
    $threads;
}

#-------------------------------------------


sub toBeThreaded($@)
{   my $self = shift;
    $_->toBeThreaded(@_) foreach @{$self->{MBM_threads}};
}

#-------------------------------------------


sub toBeUnthreaded($@)
{   my $self = shift;
    $_->toBeUnthreaded(@_) foreach @{$self->{MBM_threads}};
}

#-------------------------------------------


sub decodeFolderURL($)
{   my ($self, $name) = @_;

    return unless
       my ($type, $username, $password, $hostname, $port, $path)
          = $name =~ m!^(\w+)\:             # protocol
                       (?://
                          (?:([^:@./]*)     # username
                            (?:\:([^@/]*))? # password
                           \@)?
                           ([\w.-]+)?       # hostname
                           (?:\:(\d+))?     # port number
                        )?
                        (.*)                # foldername
                      !x;

    $username ||= $ENV{USER} || $ENV{LOGNAME};

    $password ||= '';        # decode password from url
    $password =~ s/\+/ /g;
    $password =~ s/\%([A-Fa-f0-9]{2})/chr hex $1/ge;

    $hostname ||= 'localhost';
    $path     ||= '=';

    ( type        => $type,     folder      => $path
    , username    => $username, password    => $password
    , server_name => $hostname, server_port => $port
    );
}

#-------------------------------------------


1;
