use strict;
use warnings;

package Mail::Message::Field::Full;
our $VERSION = 2.037;  # Part of Mail::Box
use base 'Mail::Message::Field';

use Mail::Message::Field::Attribute;

use utf8;
use Encode ();
use MIME::QuotedPrint ();

use Carp;
my $atext = q[a-zA-Z0-9!#\$%&'*+\-\/=?^_`{|}~];  # from RFC

my %implementation
 = ( from => 'Addresses', to  => 'Addresses', sender     => 'Addresses'
   , cc   => 'Addresses', bcc => 'Addresses', 'reply-to' => 'Addresses'
   , date => 'Date'
   );

sub new($;$$@)
{   my ($class, $name, $body) = splice(@_, 0, 3);

    my @attrs;
    push @attrs, shift
        while @_ && ref $_[0] && $_[0]->isa('Mail::Message::Field::Attribute');

    my %args   = @_;

    # Attributes preferably stored in array to protect order.
    my $attr = $args{attributes} ||= [];
    $attr    = $args{attribures} = [ %$attr ]   if ref $attr eq 'HASH';
    unshift @$attr, @attrs;

    return $class->SUPER::new(%args, name => $name, body => $body)
       if $class ne __PACKAGE__;

    # Look for best class to suit this field

    (my $type = lc $name) =~ s/^Resent\-//;
    my $myclass
      = $implementation{$type} ? $implementation{$type}
#     : $args{is_structured}   ? 'Structured'
      : $args{is_structured}   ? 'Full'
      :                          'Unstructured';

    $myclass = "Mail::Message::Field::$myclass";
    eval "require $myclass";
    return if $@;

    $myclass->SUPER::new(%args, name => $name, body => $body);
}

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);

    $self->{MMFF_name}       = $args->{name};
    $self->{MMFF_structured} = $args->{is_structured};

    my $body = $args->{body};
    if(index($body, "\n") >= 0)
    {   # body is already folded: remember how
        $self->{MMFF_body} = $body;
        $body =~ s/\n//g;   # parts store unfolded versions
    }
    $body =~ s/^\s+//;
    $self->{MMFF_parts} = length $body ? [ $body ] : [];

    $self->addExtra($args->{extra})
        if exists $args->{extra};

    my $attr = $args->{attributes};
    while(@$attr)
    {   my $name = shift @$attr;
        if(ref $name) { $self->attribute($name) }
        else          { $self->attribute($name, shift @$attr) }
    }

    $self;
}

sub from($@)
{   my ($class, $field) = (shift, shift);
    defined $field ?  $class->new($field->Name, $field->folded, @_) : ();
}

sub addAttribute($;@)
{   my $self = shift;

    my $attr = ref $_[0] ? shift : Mail::Message::Field::Attribute->new(@_);
    return undef unless $attr;

    unless($self->{MMFF_structured})
    {   $self->log(ERROR => "Attributes cannot be added to unstructured fields:\n"
               . "  Field: ".$self->Name. " Attribute: " .$attr->name);
        return;
    }

    my $name  = lc $attr->name;
    if(my $old =  $self->{MMFF_attrs}{$name})
    {   $old->mergeComponent($attr);
        return $old;
    }
    else
    {   $self->{MMFF_attrs}{$name} = $attr;
        push @{$self->{MMFF_parts}}, $attr;
        delete $self->{MMFF_body};
        return $attr;
    }
}

sub attribute($;$)
{   my ($self, $name) = (shift, shift);
    @_ ? $self->addAttribute($name, shift) : $self->{MMFF_attrs}{lc $name};
}

sub attributes() { values %{shift->{MMFF_attrs}} }

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

sub addComment($@)
{   my $self = shift;

    unless($self->{MMFF_structured})
    {   $self->log(ERROR => "Comments cannot be added to unstructured fields:\n"
                  . "  Field: ".$self->Name. " Comment: @_");
        return;
    }

    return undef
       if ! defined $_[0] || ! CORE::length($_[0]);

    my $comment = $self->createComment(@_);
    push @{$self->{MMFF_parts}}, $comment;
    delete $self->{MMFF_body};

    $comment;
}

sub addExtra($)
{   my ($self, $extra) = @_;

    unless($self->{MMFF_structured})
    {   $self->log(ERROR => "Extras cannot be added to unstructured fields:\n"
               . "  Field: ".$self->Name. " Extra: ".$extra);
        return;
    }

    if(defined $extra && length $extra)
    {   push @{$self->{MMFF_parts}}, '; '.$extra;
        delete $self->{MMFF_body};
    }

    $self;
}

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

sub addPhrase($)
{   my ($self, $string) = (shift, shift);

    return undef
         unless defined $string && CORE::length($string);

    my $phrase = $self->createPhrase($string);

    push @{$self->{MMFF_parts}}, $phrase;
    delete $self->{MMFF_body};
    $phrase;
}

sub clone()
{   my $self = shift;
    croak;
}

sub length()
{   my $self = shift;
    croak;
}

sub name() { lc shift->{MMFF_name}}

sub Name() { shift->{MMFF_name}}

sub folded(;$)
{   my $self = shift;
    return $self->{MMFF_name}.':'.$self->foldedBody
        unless wantarray;

    my @lines = $self->foldedBody;
    my $first = $self->{MMFF_name}. ':'. shift @lines;
    ($first, @lines);
}

sub unfoldedBody($;@)
{   my $self = shift;
    if(@_)
    {   my $part = join ' ', @_;
        $self->{MMFF_body}  = $self->fold($self->{MMFF_name}, $part);
        $self->{MMFF_parts} = [ $part ];
        return $part;
    }

    join(' ', @{$self->{MMFF_parts}});
}

sub foldedBody($)
{   my ($self, $body) = @_;

       if(@_==2) { $self->{MMFF_body} = $body }
    elsif($body = $self->{MMFF_body}) { ; }
    else
    {   # Create a new folded body from the parts.
        $self->{MMFF_body} = $body
           = $self->fold($self->{MMFF_name}, join(' ', @{$self->{MMFF_parts}}));
    }

    wantarray ? (split /^/, $body) : $body;
}

sub decodedBody()
{   my $self = shift;
    $self->decode($self->unfoldedBody, @_);
}

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

        my $take = 72 - CORE::length($pre);
        while(CORE::length($qp) > $take)
        {   $qp =~ s#^(.{$take}.?.?[^=][^=])## or warn $qp;
            $ready .= "$pre$1?= ";
        }
        $ready .= "$pre$qp?=" if CORE::length $qp;
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

    Encode::encode($charset, $decoded, 0);
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

sub consumePhrase($)
{   my ($thing, $string) = @_;

    if($string =~ s/^\s*\"((?:[^"\\]*|\\.)*)\"// )
    {   (my $phrase = $1) =~ s/\\\"/"/g;
        return ($phrase, $string);
    }

    if($string =~ s/^\s*([$atext\ \t.]+)//o )
    {   (my $phrase = $1) =~ s/\s+$//;
        $phrase =~ s/\s+$//g;
        return CORE::length($phrase) ? ($phrase, $string) : (undef, $_[1]);
    }

    (undef, $string);
}

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

sub consumeDotAtom($)
{   my ($self, $string) = @_;
    my ($atom, $comment);

    while(1)
    {   (my $c, $string) = $self->consumeComment($string);
        if(defined $c) { $comment .= $c; next }

        last unless $string =~ s/(\s*[$atext]+(?:\.[$atext]+)*)//o;

        $atom .= $1;
    }

    ($atom, $string, $comment);
}

1;
