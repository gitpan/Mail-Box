#!/usr/bin/perl
#
# Test processing of addresses
#

use Test::More;
use strict;
use warnings;

package Mail::Message::Field::Addresses;   # define package name
package main;

BEGIN {
   if($] < 5.007003)
   {   plan skip_all => "Requires module Encode which requires Perl 5.7.3";
       exit 0;
   }

   eval 'require Mail::Message::Field::Addresses';
   if($@)
   {
warn $@;
       plan skip_all => 'Extended attributes not available (install Encode?)';
       exit 0;
   }
   else
   {   plan tests => 96;
   }
}

use Tools;

my $mmfa  = 'Mail::Message::Field::Address';
my $mmfag = 'Mail::Message::Field::AddrGroup';
my $mmfas = 'Mail::Message::Field::Addresses';

#
# Test single addresses
#

my $ad = $mmfa->new(phrase => 'Mark Overmeer', username => 'markov',
   domain => 'cpan.org', comment => 'This is me!');
ok(defined $ad,                                    'Created ad');
isa_ok($ad, $mmfa);
is($ad->name, 'Mark Overmeer');
is($ad->address, 'markov@cpan.org');
is($ad->comment, 'This is me!');
is($ad->string, '"Mark Overmeer" <markov@cpan.org> (This is me!)');

#
# Test whole field (Addresses)
#

my $cc = $mmfas->new('Cc');
ok(defined $cc,                                    'Create cc');
isa_ok($cc, $mmfas);

my $jd = '"John Doe" <jdoe@machine.example>';
$cc = $mmfas->new(Cc => $jd);
ok(defined $cc,                                    'parsing joe');
my @g = $cc->groups;
cmp_ok(scalar @g, '==', 1);
my $g0 = $g[0];
ok(defined $g0);
isa_ok($g0, 'Mail::Message::Field::AddrGroup');
is($g0->name, '');
my @ga = $g0->addresses;
cmp_ok(scalar @ga, '==', 1,                        'address from group');
isa_ok($ga[0], 'Mail::Message::Field::Address');
is($g0->string, $jd,                               'group string is ok'); 
is("$g0", $jd,                                     'gr stringification is ok'); 

my @a = $cc->addresses;
cmp_ok(scalar @a, '==', 1,                         'all address');
my $a0 = $a[0];
ok(defined $a0);
isa_ok($a0, 'Mail::Message::Field::Address');

is($a0->name, 'John Doe');
is($a0->address, 'jdoe@machine.example');
is($a0->username, 'jdoe');
is($a0->domain, 'machine.example');

is($cc->string, "Cc: $jd\n",                       'line string');
$cc->beautify;
is($cc->string, "Cc: $jd\n",                       'line string');
is("$cc", $jd,                                     'line stringification');

#
# Checking various strings which are mentioned in rfc2822
#

my $c = '"Joe Q. Public" <john.q.public@example.com>,
 Mary Smith <mary@x.test>, jdoe@example.org, Who? <one@y-me.test>';
$cc = $mmfas->new('Cc' => $c);
ok(defined $cc,                           'Parsed Joe Q. Public');
@g = $cc->groups;
cmp_ok(scalar @g, '==', 1,               'one group');
$g0 = $g[0];
ok(defined $g0);
isa_ok($g0, 'Mail::Message::Field::AddrGroup');
is($g0->name, '');
@a = $g0->addresses;
cmp_ok(scalar @a, '==', 4,               'four addresses in group');

# the collections are not ordered (hash), so we need to enforce some
# order for the tests.
@a = sort { $a->address cmp $b->address } @a;

ok(defined $a[0]);
isa_ok($a[0], 'Mail::Message::Field::Address');
isa_ok($a[1], 'Mail::Message::Field::Address');
isa_ok($a[2], 'Mail::Message::Field::Address');
isa_ok($a[3], 'Mail::Message::Field::Address');

ok(!$a[0]->phrase,                       "checking on jdoe");
ok(!$a[0]->comment);
is($a[0]->username, 'jdoe');
is($a[0]->domain, 'example.org');

is($a[1]->phrase, 'Joe Q. Public',       "checking Joe's identity");
is($a[1]->username, 'john.q.public');
is($a[1]->domain, 'example.com');
is($a[1]->address, 'john.q.public@example.com');
is($a[1]->string, '"Joe Q. Public" <john.q.public@example.com>');

is($a[2]->phrase, 'Mary Smith',          "checking Mary's id");
is($a[2]->username, 'mary');
is($a[2]->domain, 'x.test');

is($a[3]->phrase, 'Who?',                "checking Who?");
is($a[3]->username, 'one');
is($a[3]->domain, 'y-me.test');
is($a[3]->address, 'one@y-me.test');
is($a[3]->string, 'Who? <one@y-me.test>');

is($cc->string, "Cc: $c");
$cc->beautify;
is($cc->string, <<'REFOLDED');
Cc: Who? <one@y-me.test>, jdoe@example.org, "Mary Smith" <mary@x.test>,
 "Joe Q. Public" <john.q.public@example.com>
REFOLDED

# Next!

my $c3 = <<'COMPLEX';
<boss@nil.test>, "Giant; \"Big\" Box" <sysservices@example.net>,
 A Group:Chris Jones <c@a.test>,joe@where.test,John <jdoe@one.test>;
 Undisclosed recipients:;
 "Mary Smith: Personal Account" <smith@home.example>,
 Jane Brown <j-brown@other.example>
COMPLEX

$cc = $mmfas->new(Cc => $c3);
ok(defined $cc,                                    'Parsed complex');
@g = $cc->groups;
cmp_ok(scalar @g, '==', 3);
@g = sort {$a->name cmp $b->name} @g;

is($g[0]->name, '');
cmp_ok($g[0]->addresses, '==', 4);
my @u = sort map {$_->username} $g[0]->addresses;
cmp_ok(scalar @u, '==', 4);
is($u[0], 'boss');
is($u[1], 'j-brown');
is($u[2], 'smith');
is($u[3], 'sysservices');

is($g[1]->name, 'A Group');
cmp_ok($g[1]->addresses, '==', 3);

is($g[2]->name, 'Undisclosed recipients');
cmp_ok($g[2]->addresses, '==', 0);
is($cc->string, "Cc: $c3");
$cc->beautify;
is($cc->string, <<'REFOLDED');
Cc: "Giant; \"Big\" Box" <sysservices@example.net>, boss@nil.test,
 "Jane Brown" <j-brown@other.example>,
 "Mary Smith: Personal Account" <smith@home.example>,
 A Group: John <jdoe@one.test>, joe@where.test, "Chris Jones" <c@a.test>;
 Undisclosed recipients: ;
REFOLDED

# Next !

my $c2 = <<'PETE';
Pete(A wonderful \) chap) <pete(his account)@silly.test(his host)>,
 A Group(Some people)
     :Chris Jones <c@(Chris's host.)public.example>,
         joe@example.org,
  John <jdoe@one.test> (my dear friend); (the end of the group)
PETE

$cc = $mmfas->new(Cc => $c2);
ok(defined $cc,                                    'Parsed pete');
@g = $cc->groups;
cmp_ok(scalar @g, '==', 2);
is($g[0]->name, '');
is($g[1]->name, 'A Group');
@a = $g[0]->addresses;
cmp_ok(scalar @a, '==', 1);
$a0 = $a[0];
is($a0->phrase, 'Pete');
is($a0->username, 'pete');
is($a0->domain, 'silly.test');
is($a0->address, 'pete@silly.test');
ok(!defined $a0->comment);

@a = $g[1]->addresses;
cmp_ok(scalar @a, '==', 3);
$a0 = $g[1]->find('Chris Jones');
ok(defined $a0,                                    'found chris');
is($a0->phrase, 'Chris Jones');
is($a0->username, 'c');
is($a0->domain, 'public.example');
ok(!defined $a0->comment);

$a0 = $g[1]->find('John');
ok(defined $a0,                                    'found john');
is($a0->phrase, 'John');
is($a0->username, 'jdoe');
is($a0->domain, 'one.test');
is($a0->comment, 'my dear friend');

is($g[1]->string, 'A Group: John <jdoe@one.test> (my dear friend), joe@example.org, "Chris Jones" <c@public.example>;');

is($cc->string, "Cc: $c2");
$cc->beautify;
is($cc->string, <<'REFOLDED');
Cc: Pete <pete@silly.test>, A Group: John <jdoe@one.test> (my dear friend),
 joe@example.org, "Chris Jones" <c@public.example>;
REFOLDED

__END__
Cc:(Empty list)(start)Undisclosed recipients  :(nobody(that I know))  ;
From  : John Doe <jdoe@machine(comment).  example>
Mary Smith <@machine.tld:mary@example.net>, , jdoe@test   . example
