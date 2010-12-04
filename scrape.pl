#!/usr/bin/perl
use strict;
use WWW::Mechanize;
use Data::Dumper;
use JSON::Any;
use XML::Atom::SimpleFeed;
use File::Slurp;
use List::Util;
use DateTime;
use POSIX qw/strftime/;
use Text::vCard::Addressbook;
use pQuery;

my $DIR = "data";

my $mech = WWW::Mechanize->new();
# The parlament doesn't like lwp-www. Thus, we lie.
$mech->agent_alias('Windows IE 6');

sub now { strftime('%Y-%m-%dT%H:%M:%SZ',gmtime()) };
my $now = now();

my $json = JSON::Any->new();

if(!-d $DIR) {
	mkdir($DIR)||die("Error creating data dir $DIR: $!");
}

$mech->get(q{http://www.parlament.cat/web/composicio/ple-parlament/diputats-fotos?p_pant=CO});
if(!$mech->response->is_success()) {
	die("Error getting parlament data");
}
my $html = $mech->content();
my %dip = ($html=~m,<a .*?href="/web/composicio/diputats-fitxa\?p_codi=(\d+)".*?>(.*?)</a>,igs);

write_file("$DIR/diputats.json",$json->encode(\%dip));

 
my $feed = XML::Atom::SimpleFeed->new(
	title   => 'Parlament de Catalunya',
	link    => {rel=>'via',href=>q{http://www.parlament.cat/web/composicio/ple-parlament/diputats-fotos?p_pant=CO}},
	updated => $now,
	author => 'opendatabcn.org',
	id      => "tag:cat.parlament.diputat.list",
);

foreach my $id (sort {$a<=>$b} keys %dip) {
	$feed->add_entry(
		title     => $dip{$id},
		link      => {rel=>'via',href=>qq{http://www.parlament.cat/web/composicio/diputats-fitxa?p_codi=$id}},
		link      => {rel=>'related',href=>qq{diputats/$id.vcard},type=>'text/x-vcard',title=>'vCard'},
		link      => {rel=>'related',href=>qq{diputats/$id.atom},tyle=>'application/atom+xml',title=>'Atom'},
		id      => "tag:cat.parlament.diputat:$id",
		summary   => $dip{$id},
		updated   => $now,
		category  => 'Atom',
		category  => 'Miscellaneous',
	);
}
write_file("$DIR/diputats.atom",$feed->as_string);

foreach my $id (keys %dip) {
	print "Doing $id: $dip{$id}\n";
	$mech->get(qq{http://www.parlament.cat/web/composicio/diputats-fitxa?p_codi=$id});
	if(!$mech->response->is_success()) {
		warn("Error getting data for diputat/$id");
		next;
	}
	$html = $mech->content();
	my $pq = pQuery($html);
	my(%data,@key,@val);
	$pq->find('.filiacio dt')->each(sub{
		my $str=pQuery($_)->text();
		$str =~s/:$//;
		$str =~s/\s+/_/g;
		$str = uc($str);
		push @key,$str;
	});
	$pq->find('.filiacio dd')->each(sub{push @val, pQuery($_)->text()});
	%data = map{$_=>shift(@val)} @key;
	print Dumper(\%data);
	my $ab = Text::vCard::Addressbook->new();
	my $vcard = $ab->add_vcard();
	my %args = (
		FN => $dip{$id},
		TITLE => [],
	);
	foreach my $entry ($html=~m,<address>(.*?)</address>,igs) {
		$entry=~s,[\n\r],,igs;
		$entry=~s,\s+, ,igs;
		my($addr);
		my $address = $vcard->add_node({
			'node_type' => 'ADR',
		});
		foreach my $line (split(/<br>/,$entry)) {
			$line=~s,\s+$,,igs;
			$line=~s,^\s+,,igs;
			if($line=~m,^Tel\.? (.*?)$,) {
#				$vcard->tel($1);
			} elsif($line=~m,^Fax\.? (.*?)$,) {
			} else {
				if($line=~m,^(\d{5}) (.*?),) {
					$address->city($2);
				} else {
					$address->street($1);
				}
			}
		}
	}
	while(my($key,$val)=each(%args)) {
		$vcard->$key($val);
	}
	write_file("$DIR/$id.vcard",$ab->export());
	exit;
}
