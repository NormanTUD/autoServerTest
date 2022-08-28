use strict;
use warnings;
use strict;
use LWP::UserAgent;
use Data::Dumper;
use Term::ANSIColor;
use Net::SMTP;

# Try --help for a good overview of parameters and an example!

my $ua = LWP::UserAgent->new(timeout => 10);
$ua->env_proxy;

my %options = (
	debug => 0,
	timeout => 10,
	download_check_url => [],
	smtp_host => "",
	from_email => '',
	to_email => [],
	send_mail => 0,
	show_succeeded_tests => 0
);

analyze_args(@ARGV);

sub msg (@) {
	for (@_) {
		warn color("blue").$_.color("reset")."\n";
	}
}

sub e (@) {
	my $exit_code = shift;
	for (@_) {
		warn color("red").$_.color("reset")."\n";
	}

	exit $exit_code;
}

sub w (@) {
	for (@_) {
		warn color("yellow").$_.color("reset")."\n";
	}
}

sub debug (@) {
	return unless $options{debug};
	for (@_) {
		warn "DEBUG: $_\n";
	}
}

sub help {
	print <<EOF;
@{[color("Blue")]}autoServerTest:@{[color("reset")]}
A script that checks if a website is OK, and if not, sends an email

@{[color("Blue")]}Example:@{[color("reset")]}

perl test.pl --download_check_url=http://google.de --download_check_url=a.asdasd --show_succeeded_tests --send_mail --smtp_host=127.0.0.1 --from_email=test.bla --to_email=asdaa.de --debug

@{[color("Blue")]}General:@{[color("reset")]}
--debug						Enables debug options


@{[color("Blue")]}Website-checks:@{[color("reset")]}
--download_check_url=http://google.de		Check this url (can be used multiple times!)
--timeout=X					Timeout (in seconds, default 10)

@{[color("Blue")]}Email:@{[color("reset")]}
--send_mail					Send email (if enabled, all --from_email, --to_email and --smtp_host need to be set)
--from_email=email\@address.com			This email will be used for senders
--to_email=email\@address.com			Emails will be send to this (can be used multiple times for several receivers)
--smtp_host=127.0.0.1				This host will be used for sending emails
--show_succeeded_tests				Show tests that have succeeded
EOF

	exit($_[0]);
}

sub analyze_args {
	for (@_) {
		if(/^--debug$/) {
			$options{debug} = 1;
		} elsif(/^--help$/) {
			help(0);
		} elsif(/^--timeout=(\d+)$/) {
			$options{timeout} = $1;
		} elsif(/^--download_check_url=(.+)$/) {
			push @{$options{download_check_url}}, $1;
		} elsif(/^--from_email=(.+)$/) {
			$options{from_email} = $1;
		} elsif(/^--to_email=(.+)$/) {
			push @{$options{to_email}}, $1;
		} elsif(/^--smtp_host=(.+)$/) {
			$options{smtp_host} = $1;
		} elsif(/^--send_mail$/) {
			$options{send_mail} = 1;
		} elsif(/^--show_succeeded_tests$/) {
			$options{show_succeeded_tests} = 1;
		} else {
			w "Invalid parameter $_\n\n";

			help(1);
		}
	}

	if($options{send_mail}) {
		e 2, "--smtp_host not defined" if !$options{smtp_host}; 
		e 3, "--from_email not defined" if !$options{from_email}; 
		e 4, "--to_email not defined" if !@{$options{to_email}}; 
	}
}



sub download_is_ok {
	my $url = shift;
	my $timeout = shift // $options{timeout};
	debug "download_is_ok($url)";

	my $ua = LWP::UserAgent->new(timeout => $timeout);
	$ua->env_proxy;

	my $response = $ua->get($url);

	if ($response->is_success) {
		debug "download_is_ok($url) -> OK";
		#print $response->decoded_content;
		return +{ test => "download_is_ok($url)", msg => $response->status_line, status => 'ok' };
	} else {
		w "download_is_ok($url) -> ERROR";
		w $response->status_line;

		return +{ test => "download_is_ok($url)", msg => $response->status_line, status => 'error' };
	}
}

# http://billauer.co.il/blog/2013/01/perl-sendmail-exim-postfix-test/
sub send_mail {
	my ($subject, $body) = @_;

	debug("send_mail($subject, $body)");

	my $msg = "MIME-Version: 1.0\n".
	"From: $options{from_email}\n".
	"To: " . (ref($options{to_email}) ? join(';', @{$options{to_email}}) : $options{to_email})."\n".
	"Subject: $subject\n\n".
	$body;

	my $smtp = Net::SMTP->new($options{smtp_host},
		Debug => $options{debug},
		Port => 587,
	);

	if(!defined($smtp) || !($smtp)) {
		return { test => "send_mail", status => "error", "msg" => "SMTP ERROR: Unable to open smtp session." };
	}

	if (!($smtp->mail($options{from_email}))) {
		return { test => "send_mail", status => "error", "msg" => "Failed to set FROM address" };
	}

	if (!($smtp->recipient( ( ref($options{to_email}) ? @{$options{to_email}}: $options{to_email})))) {
		return { test => "send_mail", status => "error", "msg" => "Failed to set receipient" };
	}

	$smtp->data($msg);

	$smtp->quit;

	return { test => "send_mail", status => "ok", "msg" => "" };
}

sub main {
	debug "main";

	my @tests = ();

	for (@{$options{download_check_url}}) {
		my $result = download_is_ok($_);
		debug Dumper $result;
		push @tests, $result;
	}

	my @mail_failed_part = ();
	my @mail_succeeded_part = ();

	for (@tests) {
		if($_->{status} eq "ok") {
			push @mail_succeeded_part, $_->{test}.": ".$_->{status}.", ".$_->{msg};
		} else {
			push @mail_failed_part, "!!! ".$_->{test}.": ".$_->{status}.", ".$_->{msg}." !!! ";
		}
	}

	my $mail = "";
	if(@mail_failed_part) {
		$mail .= "Failed:\n\n".join("\n", @mail_failed_part)."\n\n";
	}
	if(@mail_succeeded_part && $options{show_succeeded_tests}) {
		$mail .= "OK:\n\n".join("\n", @mail_succeeded_part)."\n";
	}

	msg $mail;

	if($options{send_mail}) {
		my $mail_result = send_mail(@mail_failed_part ? "TEST(S) FAILED!" : "All tests ok", $mail);
		if($mail_result->{status} eq "error") {
			w Dumper $mail_result;
		} else {
			debug Dumper $mail_result;
		}
	}
}

main();
