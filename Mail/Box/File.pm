use strict;
package Mail::Box::File;
our $VERSION = 2.025;  # Part of Mail::Box
use base 'Mail::Box';

use Mail::Box::File::Message;

use Mail::Message::Body::Lines;
use Mail::Message::Body::File;
use Mail::Message::Body::Delayed;
use Mail::Message::Body::Multipart;

use Mail::Message::Head;

use Carp;
use File::Copy;
use File::Spec;
use File::Basename;
use POSIX ':unistd_h';
use IO::File ();

my $default_folder_dir = exists $ENV{HOME} ? $ENV{HOME} . '/Mail' : '.';
my $default_extension  = '.d';

sub _default_body_type($$)
{   my $size = shift->guessBodySize || 0;
    'Mail::Message::Body::'.($size > 10000 ? 'File' : 'Lines');
}

sub init($)
{   my ($self, $args) = @_;
    $args->{folderdir}        ||= $default_folder_dir;
    $args->{body_type}        ||= \&_default_body_type;

    $self->SUPER::init($args);

    my $sub_extension          = $self->{MBM_sub_ext}
       = $args->{subfolder_extension} || $default_extension;

    my $filename               = $self->{MBF_filename}
       = (ref $self)->folderToFilename
           ( $self->name
           , $self->folderdir
           , $sub_extension
           );

    return unless -e $filename;

    $self->{MBM_policy}        = $args->{write_policy};

    my $lockdir   = $filename;
    $lockdir      =~ s!/([^/]*)$!!;
    my $extension = $args->{lock_extension} || '.lock';
    $self->locker->filename
      ( File::Spec->file_name_is_absolute($extension) ? $extension
      : $extension =~ m!^\.!  ? "$filename$extension"
      :                         File::Spec->catfile($lockdir, $extension)
      );

    # Check if we can write to the folder, if we need to.

    if($self->writable && ! -w $filename)
    {   $self->log(WARNING => "Folder $filename is write-protected.");
        $self->{MB_access} = 'r';
    }

    # Start parser if reading is required.

    return $self unless $self->{MB_access} =~ m/r/;
    $self->parser ? $self : undef;
}

sub organization() { 'FILE' }

sub create($@)
{   my ($class, $name, %args) = @_;
    my $folderdir = $args{folderdir} || $default_folder_dir;
    my $extension = $args{subfolder_extension} || $default_extension;
    my $filename  = $class->folderToFilename($name, $folderdir, $extension);

    return $class if -f $filename;

    my $dir       = dirname $filename;
    $class->log(ERROR => "Cannot create directory $dir for $name"), return
        unless -d $dir || mkdir $dir, 0755;

    if(-d $filename)
    {   # sub-dir found, start simulating sub-folders.  The sub-folder dir
        # is moved to make place for this real folder.
        move $filename, $filename . $extension;
    }

    if(my $create = IO::File->new($filename, 'w'))
    {   $create->close;
    }
    else
    {   warn "Cannot create folder $name: $!\n";
        return;
    }

    $class;
}

sub foundIn($@)
{   my $class = shift;
    my $name  = @_ % 2 ? shift : undef;
    my %args  = @_;
    $name   ||= $args{folder} or return;

    my $folderdir = $args{folderdir} || $default_folder_dir;
    my $extension = $args{subfolder_extension} || $default_extension;
    my $filename  = $class->folderToFilename($name, $folderdir, $extension);

    if(-d $filename)      # fake empty folder, with sub-folders
    {   return 1 unless -f File::Spec->catfile($filename, '1')   # MH
                     || -d File::Spec->catdir($filename, 'cur'); # Maildir
    }

    return 0 unless -f $filename;
    return 1 if -z $filename;      # empty folder is ok

    my $file = IO::File->new($filename, 'r') or return 0;
    local $_;                      # Save external $_
    while(<$file>)
    {   next if /^\s*$/;
        $file->close;
        return m/^From /;
    }

    return 1;
}

sub filename() { shift->{MBF_filename} }

#head2 Closing folders

sub close(@)
{   my $self = $_[0];            # be careful, we want to set the calling
    undef $_[0];                 #    ref to undef, as the SUPER does.
    shift;

    $self->parserClose;
    $self->SUPER::close(@_);
}

#head2 The messages

sub scanForMessages(@) {shift}

sub listSubFolders(@)
{   my ($thingy, %args)  = @_;
    my $class      = ref $thingy || $thingy;

    my $skip_empty = $args{skip_empty} || 0;
    my $check      = $args{check}      || 0;
    my $extension  = $args{subfolder_extension} || $default_extension;

    my $folder     = exists $args{folder} ? $args{folder} : '=';
    my $folderdir  = exists $args{folderdir}
                   ? $args{folderdir}
                   : $default_folder_dir;

    my $dir        = ref $thingy  # Mail::Box::File
                   ? $thingy->filename
                   : $class->folderToFilename($folder, $folderdir, $extension);

    my $real       = -d $dir ? $dir : "$dir$extension";
    return () unless opendir DIR, $real;

    # Some files have to be removed because they are created by all
    # kinds of programs, but are no folders.

    my @entries = grep { ! m/\.lo?ck$/ && ! m/^\./ } readdir DIR;
    closedir DIR;

    # Look for files in the folderdir.  They should be readable to
    # avoid warnings for usage later.  Furthermore, if we check on
    # the size too, we avoid a syscall especially to get the size
    # of the file by performing that check immediately.

    my %folders;  # hash to immediately un-double names.

    foreach (@entries)
    {   my $entry = File::Spec->catfile($real, $_);
        next unless -r $entry;
        if( -f _ )
        {   next if $args{skip_empty} && ! -s _;
            next if $args{check} && !$class->foundIn($entry);
            $folders{$_}++;
        }
        elsif( -d _ )
        {   # Directories may create fake folders.
            if($args{skip_empty})
            {   opendir DIR, $entry or next;
                my @sub = grep !/^\./, readdir DIR;
                closedir DIR;
                next unless @sub;
            }

            (my $folder = $_) =~ s/$extension$//;
            $folders{$folder}++;
        }
    }

    keys %folders;
}

sub openSubFolder($@)
{   my ($self, $name) = (shift, shift);
    $self->openRelatedFolder(@_, folder => "$self/$name");
}

sub parser()
{   my $self = shift;

    return $self->{MBM_parser}
        if defined $self->{MBM_parser};

    my $source = $self->filename;

    my $access = $self->{MB_access} || 'r';
    $access = 'r+' if $access eq 'rw' || $access eq 'a';

    my $locker = $self->locker;
    unless($locker->lock)
    {   $self->log(WARNING =>
                   "Couldn't get a lock on folder $self (file $source)");
        return;
    }

    my $parser = $self->{MBM_parser}
       = Mail::Box::Parser->new
       ( filename  => $source
       , mode      => $access
       , trusted   => $self->{MB_trusted}
       , $self->logSettings
       ) or return;

    $parser->pushSeparator('From ');
    $parser;
}

sub parserClose()
{   my $self   = shift;
    my $parser = delete $self->{MBM_parser} or return;
    $parser->stop;    # but there may be more handles out-there which
                      # can start the parser again.

    $self->locker->unlock;
    $self;
}

sub readMessages(@)
{   my ($self, %args) = @_;

    my $filename = $self->filename;

    # On a directory, simulate an empty folder with only subfolders.
    return $self if -d $filename;

    my @msgopts  =
      ( $self->logSettings
      , folder     => $self
      , head_type  => $args{head_type}
      , field_type => $args{field_type}
      , trusted    => $args{trusted}
      );

    my $parser   = $self->parser;

    while(1)
    {   my $message = $args{message_type}->new(@msgopts);
        last unless $message->readFromParser($parser);
        $self->storeMessage($message);
    }

    # Release the folder.
    $self;
}

sub writeMessages($)
{   my ($self, $args) = @_;

    my $filename = $self->filename;
    if( ! @{$args->{messages}} && $self->{MB_remove_empty})
    {   unless(unlink $filename)
        {   $self->log(WARNING =>
               "Couldn't remove folder $self (file $filename): $!");
        }

        # Can the sub-folder directory be removed?  Don't mind if this
        # doesn't work (probably no subdir).
        rmdir $filename . $self->{MBM_sub_ext};

        return $self;
    }

    my $policy = exists $args->{policy} ? $args->{policy} : $self->{MBM_policy};
    $policy  ||= '';

    my $success
      = ! -e $filename       ? $self->_write_new($args)
      : $policy eq 'INPLACE' ? $self->_write_inplace($args)
      : $policy eq 'REPLACE' ? $self->_write_replace($args)
      : $self->_write_replace($args) ? 1
      : $self->_write_inplace($args);

    unless($success)
    {   $self->log(ERROR => "Unable to update folder $self.");
        return;
    }

    $self;
}

sub _write_new($)
{   my ($self, $args) = @_;

    my $filename = $self->filename;
    my $new      = IO::File->new($filename, 'w');
    return 0 unless defined $new;

    my @messages = @{$args->{messages}};
    foreach my $message (@messages)
    {   my  $newbegin  = $new->tell;
        $message->print($new);
        $message->modified(0);
    }

    $self->log(PROGRESS => "Written new folder $self with ".@messages,"msgs.");
    $new->close;
    1;
}

# First write to a new file, then replace the source folder in one
# move.  This is much slower than inplace update, but it is safer,
# The folder is always in the right shape, even if the program is
# interrupted.

sub _write_replace($)
{   my ($self, $args) = @_;

    my $filename = $self->filename;
    my $tmpnew   = $self->tmpNewFolder($filename);
    my $new      = IO::File->new($tmpnew, 'w');
    return 0 unless defined $new;
    return 0 unless open FILE, '<', $filename;

    my ($reprint, $kept) = (0,0);

    foreach my $message ( @{$args->{messages}} )
    {
        my $newbegin = $new->tell;
        my $oldbegin = $message->fileLocation;

        if($message->modified)
        {   $message->print($new);
            $message->modified(0);

            $message->moveLocation($newbegin - $oldbegin)
               if defined $oldbegin;
            $reprint++;
        }
        else
        {   my ($begin, $end) = $message->fileLocation;
            seek FILE, $begin, 0;
            my $whole;

            my $need = $end-$begin;
            my $size = read FILE, $whole, $need;
            $self->log(ERROR => 'File too short to get write message.')
               if $size != $need;

            $new->print($whole);
            $message->moveLocation($newbegin - $oldbegin);
            $kept++;
        }
    }

    $new->close;
    CORE::close FILE;

    if(move $tmpnew, $filename)
    {    $self->log(PROGRESS => "Folder $self replaced ($kept, $reprint)");
         $self->parser->takeFileInfo;
         $self->parserClose;
    }
    else
    {   $self->log(WARNING =>
            "Could not replace $filename by $tmpnew, to update $self: $!");
        unlink $tmpnew;
        return 0;
    }

    1;
}

# Inplace is currently very poorly implemented.  From the first
# location where changes appear, all messages are rewritten.

sub _write_inplace($)
{   my ($self, $args) = @_;

    my @messages = @{$args->{messages}};

    my ($msgnr, $kept) = (0, 0);
    while(@messages)
    {   my $next = $messages[0];
        last if $next->modified || $next->seqnr!=$msgnr++;
        shift @messages;
        $kept++;
    }

    if(@messages==0 && $msgnr==$self->messages)
    {   $self->log(PROGRESS => "No changes to be written to $self.");
        return 1;
    }

    $_->body->load foreach @messages;

    my $mode     = $^O =~ m/^Win/i ? 'a' : '+<';
    my $filename = $self->filename;

    return 0 unless open FILE, $mode, $filename;

    # Chop the folder after the messages which do not have to change.
    my $keepend  = $messages[0]->fileLocation;
    unless(truncate FILE, $keepend)
    {   CORE::close FILE;  # truncate impossible: try replace writing
        return 0;
    }
    seek FILE, 0, 2;       # go to end

    # Print the messages which have to move.
    my $printed = @messages;
    foreach my $message (@messages)
    {   my $oldbegin = $message->fileLocation;
        my $newbegin = tell FILE;
        $message->print(\*FILE);
        $message->moveLocation($newbegin - $oldbegin);
    }

    CORE::close FILE;
    $self->log(PROGRESS => "Folder $self updated in-place ($kept, $printed)");
    $self->parser->takeFileInfo;

    1;
}

sub appendMessages(@)
{   my $class  = shift;
    my %args   = @_;

    my @messages
      = exists $args{message}  ? $args{message}
      : exists $args{messages} ? @{$args{messages}}
      :                          return ();

    my $folder   = $class->new(@_, access => 'a');
    my $filename = $folder->filename;

    my $out      = IO::File->new($filename, 'a');
    unless($out)
    {   $class->log(ERROR => "Cannot append to $filename: $!");
        return ();
    }

    my $msgtype = 'Mail::Box::File::Message';
    my @coerced;

    foreach my $msg (@messages)
    {   my $coerced
           = $msg->isa($msgtype) ? $msg
           : $msg->can('clone')  ? $msgtype->coerce($msg->clone)
           :                       $msgtype->coerce($msg);

        $coerced->print($out);
        push @coerced, $coerced;
    }

    $out->close;
    $folder->close;
    @coerced;
}

sub folderToFilename($$$)
{   my ($class, $name, $folderdir, $extension) = @_;
    return $name if File::Spec->file_name_is_absolute($name);

    my @parts = split m!/!, $name;
    my $real  = shift @parts;
    if(@parts)
    {   my $file  = pop @parts;

        $real = File::Spec->catdir($real.(-d $real ? '' : $extension), $_)
           foreach @parts;

        $real = File::Spec->catfile($real.(-d $real ? '' : $extension), $file);
    }

    $real =~ s#^=#$folderdir/#;
    $real;
}

sub tmpNewFolder($) { shift->filename . '.tmp' }

1;
