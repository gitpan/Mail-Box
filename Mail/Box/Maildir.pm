
use strict;
package Mail::Box::Maildir;
use vars '$VERSION';
$VERSION = '2.042';
use base 'Mail::Box::Dir';

use Mail::Box::Maildir::Message;

use Carp;
use File::Copy;
use File::Spec;
use Sys::Hostname;


my $default_folder_dir = exists $ENV{HOME} ? "$ENV{HOME}/.maildir" : '.';

sub init($)
{   my ($self, $args) = @_;

    croak "No locking possible for maildir folders."
       if exists $args->{locker}
       || (defined $args->{lock_type} && $args->{lock_type} ne 'NONE');

    $args->{lock_type}   = 'NONE';
    $args->{folderdir} ||= $default_folder_dir;

    return undef
        unless $self->SUPER::init($args);

    $self;
}

#-------------------------------------------


sub create($@)
{   my ($thingy, $name, %args) = @_;
    my $class     = ref $thingy      || $thingy;
    my $folderdir = $args{folderdir} || $default_folder_dir;
    my $directory = $class->folderToDirectory($name, $folderdir);

    if($class->createDirs($directory))
    {   $class->log(PROGRESS => "Created folder Maildir $name.");
        return $class;
    }
    else
    {   $class->log(ERROR => "Cannot create Maildir folder $name.");
        return undef;
    }
}

#-------------------------------------------

sub foundIn($@)
{   my $class = shift;
    my $name  = @_ % 2 ? shift : undef;
    my %args  = @_;
    my $folderdir = $args{folderdir} || $default_folder_dir;
    my $directory = $class->folderToDirectory($name, $folderdir);

    -d File::Spec->catdir($directory, 'cur');
}

#-------------------------------------------

sub type() {'maildir'}

#-------------------------------------------

sub listSubFolders(@)
{   my ($class, %args) = @_;
    my $dir;

    if(ref $class)
    {   $dir   = $class->directory;
        $class = ref $class;
    }
    else
    {   my $folder    = $args{folder}    || '=';
        my $folderdir = $args{folderdir} || $default_folder_dir;
        $dir   = $class->folderToDirectory($folder, $folderdir);
    }

    $args{skip_empty} ||= 0;
    $args{check}      ||= 0;

    # Read the directories from the directory, to find all folders
    # stored here.  Some directories have to be removed because they
    # are created by all kinds of programs, but are no folders.

    return () unless -d $dir && opendir DIR, $dir;

    my @dirs;
    while(my $d = readdir DIR)
    {   next if $d =~ m/^(new$|tmp$|cur$|\.)/;

        my $dir = File::Spec->catfile($dir,$d);
        push @dirs, $d if -d $dir && -r _;
    }

    closedir DIR;

    # Skip empty folders.

    @dirs = grep {!$class->folderIsEmpty(File::Spec->catfile($dir, $_))} @dirs
        if $args{skip_empty};

    # Check if the files we want to return are really folders.

    return @dirs unless $args{check};
    grep { $class->foundIn(File::Spec->catfile($dir,$_)) } @dirs;
}

#-------------------------------------------

sub nameOfSubFolder($)
{   my ($self, $name) = @_;
    File::Spec->catfile($self->directory, $name);
}

#-------------------------------------------

sub openSubFolder($@)
{   my ($self, $name) = (shift, shift);
    $self->createDirs($self->nameOfSubFolder($name));
    $self->SUPER::openSubFolder($name, @_);
}

#-------------------------------------------

my $uniq = rand 1000;


sub coerce($)
{   my ($self, $message) = @_;

    my $is_native = $message->isa('Mail::Box::Maildir::Message');
    my $coerced   = $self->SUPER::coerce($message);

    my $basename
      = $is_native
      ? (split m!/!, $message->filename)[-1]
      : $message->timestamp .'.'. hostname .'.'. $uniq++;

    my $dir = $self->directory;
    my $tmp = File::Spec->catfile($dir, tmp => $basename);
    my $new = File::Spec->catfile($dir, new => $basename);

    if($coerced->create($tmp) && $coerced->create($new))
         {$self->log(PROGRESS => "Added Maildir message in $new") }
    else {$self->log(ERROR    => "Cannot create Maildir message file $new.") }

    $coerced->labelsToFilename unless $is_native;
    $coerced;
}

#-------------------------------------------


sub createDirs($)
{   my ($thing, $dir) = @_;

    $thing->log(ERROR => "Cannot create Maildir folder directory $dir: $!\n"), return
        unless -d $dir || mkdir $dir;

    my $tmp = File::Spec->catdir($dir, 'tmp');
    $thing->log(ERROR => "Cannot create Maildir folder subdir $tmp: $!\n"), return
        unless -d $tmp || mkdir $tmp;

    my $new = File::Spec->catdir($dir, 'new');
    $thing->log(ERROR => "Cannot create Maildir folder subdir $new: $!\n"), return
        unless -d $new || mkdir $new;

    my $cur = File::Spec->catdir($dir, 'cur');
    $thing->log(ERROR =>  "Cannot create Maildir folder subdir $cur: $!\n"), return
        unless -d $cur || mkdir $cur;

    $thing;
}

#-------------------------------------------


sub folderIsEmpty($)
{   my ($self, $dir) = @_;
    return 1 unless -d $dir;

    foreach (qw/tmp new cur/)
    {   my $subdir = File::Spec->catfile($dir, $_);
        next unless -d $subdir;

        opendir DIR, $subdir or return 0;
        my $first  = readdir DIR;
        closedir DIR;

        return 0 if defined $first;
    }

    opendir DIR, $dir or return 1;
    while(my $entry = readdir DIR)
    {   next if $entry =~
           m/^(?:tmp|cur|new|bulletin(?:time|lock)|seriallock|\..?)$/;

        closedir DIR;
        return 0;
    }

    closedir DIR;
    1;
}

#-------------------------------------------

sub readMessageFilenames
{   my ($self, $dirname) = @_;

    # Collect all files which start with a timestamp.  Ignore filenames
    # which end with '.new', because they are being created on this moment.

    opendir DIR, $dirname or return ();

    my @files
      = grep { /^\d/ && !/\.new$/ && -f File::Spec->catfile($dirname, $_) }
           readdir DIR;

    closedir DIR;

    # Sort the names.  Solve the Y2K (actually the 1 billion seconds
    # since 1970 bug) which hunts Maildir.  The timestamp, which is
    # the start of the filename will have some 0's in front, so each
    # timestamp has the same length.

    my %unified;
    m/^(\d+)/ and $unified{ ('0' x (9-length($1))).$_ } = $_ foreach @files;
    map { $unified{$_} } sort keys %unified;
}

#-------------------------------------------

sub readMessages(@)
{   my ($self, %args) = @_;

    my $directory = $self->directory;
    return unless -d $directory;

    #
    # Read all accepted messages
    #

    my $curdir  = File::Spec->catdir($directory, 'cur');
    my @cur     = $self->readMessageFilenames($curdir);
    my @log     = $self->logSettings;

    foreach my $msgfile (@cur)
    {   my $msgpath = File::Spec->catfile($directory, cur => $msgfile);
        my $head    = $args{head_delayed_type}->new(@log);
        my $message = $args{message_type}->new
         ( head      => $head
         , filename  => $msgpath
         , folder    => $self
         );

        my $body    = $args{body_delayed_type}->new(@log, message => $message);
        $message->storeBody($body) if $body;
        $self->storeMessage($message);
    }

    $self->update;   # Get new messages
    $self;
}
 
#-------------------------------------------

sub updateMessages($)
{   my ($self, %args) = @_;
    my $directory = $self->directory;
    return unless -d $directory;

    my $newdir    = File::Spec->catfile($directory, 'new');
    my @new       = $self->readMessageFilenames($newdir);
    my @log       = $self->logSettings;

    my $msgtype   = $self->{MB_message_type};
    my @newmsgs;

    foreach my $newfile (@new)
    {    
        my $msgpath = File::Spec->catfile($directory, new => $newfile);
        my $head    = $args{head_delayed_type}->new(@log);
        my $message = $args{message_type}->new
         ( head     => $head
         , filename => $msgpath
         , folder   => $self
         , fix_header => $self->{MB_fix_headers}
         , @log
         );

        my $body    = $args{body_delayed_type}->new
         ( @log
         , message  => $message
         );

        $message->storeBody($body) if $body;
        $self->storeMessage($message);

        $message->statusToLabels->labelsToFilename;
        push @newmsgs, $message->accept;
    }

    @newmsgs;
}

#-------------------------------------------

sub writeMessages($)
{   my ($self, $args) = @_;

    # Write each message.  Two things complicate life:
    #   1 - we may have a huge folder, which should not be on disk twice
    #   2 - we may have to replace a message, but it is unacceptable
    #       to remove the original before we are sure that the new version
    #       is on disk.

    my $writer    = 0;

    my $directory = $self->directory;
    my @messages  = @{$args->{messages}};

    my $tmpdir    = File::Spec->catfile($directory, 'tmp');
    die "Cannot create directory $tmpdir: $!"
        unless -d $tmpdir || mkdir $tmpdir;

    foreach my $message (@messages)
    {   next unless $message->isModified;

        my $filename = $message->filename;
        my $basename = (File::Spec->splitpath($filename))[2];

        my $newtmp   = File::Spec->catfile($directory, 'tmp', $basename);
        my $new      = IO::File->new($newtmp, 'w')
           or croak "Cannot create file $newtmp: $!";

        $message->labelsToStatus;  # just for fun
        $message->write($new);
        $new->close;

        unlink $filename;
        move $newtmp, $filename
            or warn "Cannot move $newtmp to $filename: $!\n";
    }

    # Remove an empty folder.  This is done last, because the code before
    # in this method will have cleared the contents of the directory.

    if(!@messages && $self->{MB_remove_empty})
    {   # If something is still in the directory, this will fail, but I
        # don't mind.
        rmdir File::Spec->catfile($directory, 'cur');
        rmdir File::Spec->catfile($directory, 'tmp');
        rmdir File::Spec->catfile($directory, 'new');
        rmdir File::Spec->catfile($directory);
    }

    $self;
}

#-------------------------------------------


sub appendMessages(@)
{   my $class  = shift;
    my %args   = @_;

    my @messages = exists $args{message}  ?   $args{message}
                 : exists $args{messages} ? @{$args{messages}}
                 : return ();

    my $self     = $class->new(@_, access => 'a');
    my $directory= $self->directory;
    return unless -d $directory;

    my $tmpdir   = File::Spec->catfile($directory, 'tmp');
    croak "Cannot create directory $tmpdir: $!", return
        unless -d $tmpdir || mkdir $tmpdir;

    foreach my $message (@messages)
    {   my $is_native = $message->isa('Mail::Box::Maildir::Message');
        my $coerced   = $self->SUPER::coerce($message);

        my $basename
         = $is_native
         ? (split m!/!, $message->filename)[-1]
         : $message->timestamp .'.'. hostname .'.'. $uniq++;

       my $dir = $self->directory;
       my $tmp = File::Spec->catfile($dir, tmp => $basename);
       my $new = File::Spec->catfile($dir, new => $basename);

       if($coerced->create($tmp) && $coerced->create($new))
            {$self->log(PROGRESS => "Appended Maildir message in $new") }
       else {$self->log(ERROR    =>
                "Cannot append Maildir message in $new to folder $self.") }
    }
 
    $self->close;

    @messages;
}

#-------------------------------------------


1;
