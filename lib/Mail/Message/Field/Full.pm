use strict;
use warnings;

package Mail::Message::Field::Full;
use vars '$VERSION';
$VERSION = '2.064';
use base 'Mail::Message::Field';

use utf8;
use Encode ();
use MIME::QuotedPrint ();
use Storable 'dclone';

use Mail::Message::Field::Structured;
use Mail::Message::Field::Unstructured;
use Mail::Message::Field::Addresses;
use Mail::Message::Field::URIs;

my $atext = q[a-zA-Z0-9!#\$%&'*+\-\/=?^_`{|}~];  # from RFC


use overload '""' => sub { shift->decodedBody };

#------------------------------------------


my %implementation;

BEGIN {
   $implementation{$_} = 'Addresses' foreach
      qw/from to sender cc bcc reply-to envelope-to
         resent-from resent-to resent-cc resent-bcc resent-reply-to
         resent-sender
         x-beenthere errors-to mail-follow-up x-loop delivered-to
         original-sender x-original-sender/;
   $implementation{$_} = 'URIs' foreach
      qw/list-help list-post list-subscribe list-unsubscribe list-archive
         list-owner/;
   $implementation{$_} = 'Structured' foreach
      qw/content-disposition content-type/;
#  $implementation{$_} = 'Date' foreach
#     qw/date resent-date/;
}

sub new($;$$@)
{   my $class  = shift;
    my $name   = shift;
    my $body   = @_ % 2 ? shift : undef;
    my %args   = @_;

    $body      = delete $args{body} if defined $args{body};
    unless(defined $body)
    {   (my $n, $body) = split /\s*\:\s*/s, $name, 2;
        $name = $n if defined $body;
    }
   
    return $class->SUPER::new(%args, name => $name, body => $body)
       if $class ne __PACKAGE__;

    # Look for best class to suit this field
    my $myclass = 'Mail::Message::Field::'
                . ($implementation{lc $name} || 'Unstructured');

    $myclass->SUPER::new(%args, name => $name, body => $body);
}

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);
    $self->{MMFF_name}       = $args->{name};

    my $body = $args->{body};

       if(!defined $body || !length $body || ref $body) { ; } # no body yet
    elsif(index($body, "\n") >= 0)
         { $self->foldedBody($body) }        # body is already folded
    else { $self->unfoldedBody($body) }      # body must be folded

    $self;
}

#------------------------------------------

sub clone() { dclone(shift) }

#------------------------------------------

sub name() { lc shift->{MMFF_name}}

#------------------------------------------

sub Name() { shift->{MMFF_name}}

#------------------------------------------

sub folded()
{   my $self = shift;
    return $self->{MMFF_name}.':'.$self->foldedBody
        unless wantarray;

    my @lines = $self->foldedBody;
    my $first = $self->{MMFF_name}. ':'. shift @lines;
    ($first, @lines);
}

#------------------------------------------

sub unfoldedBody($;$)
{   my ($self, $body) = (shift, shift);

    if(defined $body)
    {    $self->foldedBody(scalar $self->fold($self->{MMFF_name}, $body));
         return $body;
    }

    $body = $self->foldedBody;
    $body =~ s/^ //;
    $body =~ s/\n//g;
    $body;
}

#------------------------------------------

sub foldedBody($)
{   my ($self, $body) = @_;

    if(@_==2)
    {    $self->parse($body);
         $body =~ s/^\s*/ /;
         $self->{MMFF_body} = $body;
    }
    elsif(defined($body = $self->{MMFF_body})) { ; }
    else
    {   # Create a new folded body from the parts.
        $self->{MMFF_body} = $body
           = $self->fold($self->{MMFF_name}, $self->produceBody);
    }

    wantarray ? (split /^/, $body) : $body;
}

#------------------------------------------


sub from($@)
{   my ($class, $field) = (shift, shift);
    defined $field ?  $class->new($field->Name, $field->foldedBody, @_) : ();
}

#------------------------------------------


sub decodedBody()
{   my $self = shift;
    $self->decode($self->unfoldedBody, @_);
}

#------------------------------------------


sub createComment($@)
{   my ($thing, $comment) = (shift, shift);

    $comment = $thing->encode($comment, @_)
        if @_; # encoding required...

    # Correct dangling parenthesis
    local $_ = $comment;               # work with a copy
    s#\\[()]#xx#g;                     # remove escaped parens
    s#[^()]#x#g;                       # remove other chars
    while( s#\(([^()]*)\)#x$1x# ) {;}  # remove pairs of parens

    substr($comment, CORE::length($_), 0, '\\')
        while s#[()][^()]*$##;         # add escape before remaining parens

    $comment =~ s#\\+$##;              # backslash at end confuses
    "($comment)";
}

#------------------------------------------


sub createPhrase($)
{   my $self = shift;
    local $_ = shift;
    $_ =  $self->encode($_, @_)
        if @_;  # encoding required...

    if( m/[^$atext]/ )
    {   s#\\#\\\\#g;
        s#"#\\"#g;
        $_ = qq["$_"];
    }

    $_;
}

#------------------------------------------


sub beautify() { shift }

#------------------------------------------


sub encode($@)
{   my ($self, $utf8, %args) = @_;

    my ($charset, $lang, $encoding);

    if($charset = $args{charset})
    {   $self->log(WARNING => "Illegal character in charset '$charset'")
            if $charset =~ m/[\x00-\ ()<>@,;:"\/[\]?.=\\]/;
    }
    else { $charset = 'us-ascii' }

    if($lang = $args{language})
    {   $self->log(WARNING => "Illegal character in language '$lang'")
            if $lang =~ m/[\x00-\ ()<>@,;:"\/[\]?.=\\]/;
    }

    if($encoding = $args{encoding})
    {   unless($encoding =~ m/^[bBqQ]$/ )
        {   $self->log(WARNING => "Illegal encoding '$encoding', used 'q'");
            $encoding = 'q';
        }
    }
    else { $encoding = 'q' }

    my $encoded  = Encode::encode($charset, $utf8, 0);

    no utf8;

    my $pre      = '=?'. $charset. ($lang ? '*'.$lang : '') .'?'.$encoding.'?';
    my $ready    = '';

    if(lc $encoding eq 'q')
    {   # Quoted printable encoding
        my $qp   = $encoded;
        $qp      =~ s#([\x00-\x1F=\x7F-\xFF])#sprintf "=%02X", ord $1#ge;

        return $qp           # string only contains us-ascii?
           if !$args{force} && $qp eq $utf8;

        $qp      =~ s#([_\?])#sprintf "=%02X", ord $1#ge;
        $qp      =~ s/ /_/g;

        my $take = 70 - CORE::length($pre);
        while(CORE::length($qp) > $take+1)
        {   $qp =~ s#^(.{$take}.?.?[^=][^=])## or warn $qp;
            $ready .= "$pre$1?= ";
        }
        $ready .= "$pre$qp?=" if CORE::length($qp);
    }

    else
    {   # base64 encoding
        require MIME::Base64;
        my $maxchars = int((74-CORE::length($pre))/4) *4;
        my $bq       = MIME::Base64::encode_base64($encoded);
        $bq =~ s/\s*//gs;
        while(CORE::length($bq) > $maxchars)
        {   $ready .= $pre . substr($bq, 0, $maxchars, '') . '?= ';
        }
        $ready .= "$pre$bq?=";
    }

    $ready;
}

#------------------------------------------


sub _decoder($$$)
{   my ($charset, $encoding, $encoded) = @_;
    $charset   =~ s/\*[^*]+$//;   # string language, not used
    $charset ||= 'us-ascii';

    my $decoded;
    if(lc($encoding) eq 'q')
    {   # Quoted-printable encoded
        $encoded =~ s/_/ /g;
        $decoded = MIME::QuotedPrint::decode_qp($encoded);
    }
    elsif(lc($encoding) eq 'b')
    {   # Base64 encoded
        require MIME::Base64;
        $decoded = MIME::Base64::decode_base64($encoded);
    }
    else
    {   # unknown encodings ignored
        return $encoded;
    }

    Encode::decode($charset, $decoded, 0);
}

sub decode($@)
{   my ($self, $encoded, %args) = @_;
    if(defined $args{is_text} ? $args{is_text} : 1)
    {  # in text, blanks between encoding must be removed, but otherwise kept :(
       # dirty trick to get this done: add an explicit blank.
       $encoded =~ s/\?\=\s(?!\s*\=\?|$)/_?= /gs;
    }
    $encoded =~ s/\=\?([^?\s]*)\?([^?\s]*)\?([^?\s]*)\?\=\s*/_decoder($1,$2,$3)/gse;

    $encoded;
}

#------------------------------------------


sub parse($) { shift }

#------------------------------------------


sub consumePhrase($)
{   my ($thing, $string) = @_;

    if($string =~ s/^\s*\"((?:[^"\\]*|\\.)*)\"// )
    {   (my $phrase = $1) =~ s/\\\"/"/g;
        return ($phrase, $string);
    }

    if($string =~ s/^\s*([$atext\ \t.]+)//o )
    {   (my $phrase = $1) =~ s/\s+$//;
        return CORE::length($phrase) ? ($phrase, $string) : (undef, $_[1]);
    }

    (undef, $string);
}

#------------------------------------------


sub consumeComment($)
{   my ($thing, $string) = @_;

    return (undef, $string)
        unless $string =~ s/^\s*\(((?:[^)\\]+|\\.)*)\)//;

    my $comment = $1;
    while(1)
    {   (my $count = $comment) =~ s/\\./xx/g;

        last if $count =~ tr/(//  ==  $count =~ tr/)//;

        return (undef, $_[1])
            unless $string =~ s/^((?:[^)\\]+|\\.)*)\)//;

        $comment .= ')'.$1;
    }

    $comment =~ s/\\([()])/$1/g;
    ($comment, $string);
}

#------------------------------------------


sub consumeDotAtom($)
{   my ($self, $string) = @_;
    my ($atom, $comment);

    while(1)
    {   (my $c, $string) = $self->consumeComment($string);
        if(defined $c) { $comment .= $c; next }

        last unless $string =~ s/^\s*([$atext]+(?:\.[$atext]+)*)//o;

        $atom .= $1;
    }

    ($atom, $string, $comment);
}

#------------------------------------------

                                                                                
sub produceBody() { die }

#------------------------------------------



1;
