#!/usr/bin/env perl
use 5.010;
use strict;
use warnings;
use LWP::UserAgent;
use Getopt::Std;
use JSON::Tiny qw/decode_json/;
use Time::HiRes qw/usleep/;
use Encode qw/encode/;

$Getopt::Std::STANDARD_HELP_VERSION = 1;
sub HELP_MESSAGE {
	say STDERR "Usage: $0 -e<email for UA> -t<auth token> -c<channel id> -o<filename>";
	say STDERR "Optional arguments: -s: include timestamps";
	say STDERR "                    -u: include usernames";
}

my %opts;
getopts('e:t:c:o:su', \%opts);

for (qw/e t c o/) {
	die "Missing an option, run $0 --help\n" unless defined $opts{$_};
}

my $ua = new LWP::UserAgent;
$ua->timeout(5);
$ua->default_headers(
	new HTTP::Headers (
		User_Agent => "discord_log (mailto:$opts{e}, 1) using a regular user account. please email me if this is not okay and I will stop",
		Authorization => $opts{t}
	)
);

sub err_info {
	my $resp = shift;
	say STDERR "Request failed: ".$resp->status_line;
	say STDERR "[Enter] to print response or ^C to die";
	<>;
	say STDERR $resp->decoded_content;
	die;
}

sub get_chaninfo {
	my $chan = shift;
	# assuming global $ua
	my $resp = $ua->get("https://discordapp.com/api/v6/channels/$chan");
	err_info($resp) unless $resp->is_success;
	return decode_json $resp->decoded_content;
}

sub get_guildinfo {
	my $guild = shift;
	my $resp = $ua->get("https://discordapp.com/api/v6/guilds/$guild");
	err_info($resp) unless $resp->is_success;
	return decode_json $resp->decoded_content;
}

sub get_next_messages {
	my $chan = shift;
	my $before = shift;
	my $resp = $ua->get("https://discordapp.com/api/v6/channels/$chan/messages?limit=100"
	 . ($before != 0 ? "&before=$before" : ""));
	err_info($resp) unless $resp->is_success;
	return decode_json $resp->decoded_content;
}

sub printable_message {
	my $msg = shift;
	my $ret = "";
	$ret .= "[$msg->{timestamp}] " if $opts{s};
	$ret .= "<$msg->{author}->{username}#$msg->{author}->{discriminator}> " if $opts{u};
	$ret .= $msg->{content};
	return encode("UTF-8", $ret);
}

my $chaninfo = get_chaninfo($opts{c});
my $guildinfo = get_guildinfo($chaninfo->{guild_id});

say STDERR "Okay, archiving channel $chaninfo->{id} ($chaninfo->{name}) on server $chaninfo->{guild_id} ($guildinfo->{name})";

open my $file, ">", $opts{o} or die $!;

# Time to get all the messages
my $count = 0;
my $earliest_processed = 0;

while (1) {
	my $messages = get_next_messages($opts{c}, $earliest_processed);
	$count += scalar(@{$messages});

	# We are logging the messages backwards because it's the most practical solution given the API limitations
	say $file printable_message($_) for @{$messages};

	$earliest_processed = $messages->[scalar(@{$messages}) - 1]->{id};
	last if scalar(@{$messages}) < 100;
	
	say STDERR "Got ".scalar(@{$messages})." messages ($count so far), sleeping";
	usleep(500000);
}

say STDERR "Done. Got $count messages.";
close $file;
