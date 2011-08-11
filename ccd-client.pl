#!/usr/bin/perl -wT
# Standard XML CCD-client
# Copyright 2010 Jaakko Heusala <jhh@jhh.me>

use utf8;
use strict;
use warnings;
require LWP::UserAgent;
use HTTP::Request::Common qw(POST);
use diagnostics;
use MIME::QuotedPrint;
use open ':utf8';
use List::Util qw(sum);

use I18N::Langinfo qw(langinfo CODESET);
use Encode qw(encode decode);

#binmode STDIN, ":utf8";
binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

# Load configurations
{
	package Config;
	
	# Parse Configurations
	our $CCD_URL = 'https://ccd.sendanor.com/ccd.fcgi';
	our $BROWSER_TIMEOUT = 10;
	#$CREDENTIAL_USERNAME='ccd';
	#$CREDENTIAL_PASSWORD='';
	
	our $HOME = undef;
	if(defined $ENV{"HOME"}) {
		$HOME = $ENV{"HOME"};
		if ($HOME =~ /^(.*)$/) { $HOME = $1; } # Clean up tainted $HOME
	}
	
	our $CCD_CONFIG_DIR = undef;
	if(defined $HOME) {
		$CCD_CONFIG_DIR = "$HOME/.ccd-client";
	}
	
	our $CCD_SESSION_ID_FILE = undef;
	if(defined $CCD_CONFIG_DIR) {
		$CCD_SESSION_ID_FILE = "$CCD_CONFIG_DIR/session_id";
	}
	
	if(-e "/etc/default/ccd-client") {
		do "/etc/default/ccd-client" or die "Could not open config: $!";
	}
	
	if(defined($CCD_CONFIG_DIR) && -e $CCD_CONFIG_DIR."/config.pl") {
		do $CCD_CONFIG_DIR."/config.pl" or die "Could not open config: $!";
	}
}


# Parse JSON request
sub build_perl_request {
	my $session_id = shift;
	my @local_args = ();
	my @free_args = ();
	my %options = ();
	foreach my $arg (@_) {
		#$arg = Encode::decode_utf8( $arg );
		if($arg =~ /^--/) {
			push(@local_args, $arg);
		} elsif($arg =~ /=/) {
			my ($key, $value) = split('=', $arg, 2);
			$options{$key} = $value;
		} else {
			push( @free_args, $arg);
		}
	}
	my $command = join(' ', @free_args);
	my @args = ();
	my @empty = ();
	my %data = (command=>$command, options=>\%options, args=>\@args, free_args=>\@empty, session_id=>$session_id, 'local_args'=>\@local_args);
	return %data;
}	



# Load session ID from file
sub load_session_id {
	my $session_file = shift;
	my $session_id = "";
	if(-e $session_file) {
		open(FILE, "<:utf8", $session_file) or die "cannot open file: $session_file";
		$session_id = join("", <FILE>);
		close(FILE);
	}
	return $session_id;
}

# Save session id to file
sub save_session_id {
	my $session_file = shift;
	my $session_id = shift;
	open(FILE, ">:utf8", $session_file) or die "cannot open file: $session_file";
	print FILE $session_id;
	close(FILE);
}



# Build XML request
sub build_xml_request {
	my($session_id, @requests) = @_;
	
	my $xs1 = XML::Simple->new(ForceArray => 1, RootName=>'ccd');
	my $doc = $xs1->XMLin( "<ccd type=\"request\">" . ("<command name=\"\"></command>" x scalar(@requests)) . "</ccd>"
		, KeyAttr=>'key'
		, ForceArray => 1
	);
	if($session_id ne "") { $doc->{session_id} = $session_id; }
	
	my $i = 0;
	for my $request (@requests) {
		my %request = %{$request};
		my $command = $request{"command"};
		my %options = %{$request{"options"}};
		
		$doc->{command}->[$i]->{name} = $command;
		
		while(my ($key, $value) = each(%options)) {
			#print STDERR "[DEBUG] arg: $arg\n";
			my $ref = XMLin("<option name=\"\" value=\"\" />", ForceArray => 1, KeyAttr=>'key');
			$ref->{name} = $key;
			$ref->{value} = $value;
			push( @{$doc->{command}->[$i]->{option}}, $ref );
		}
		
		$i++;
	}
	
	return $xs1->XMLout($doc, XMLDecl=>1, KeyAttr=>'key');
}

# Perform HTTP POST
sub ccd_http_post {
	
	my ($ua, $url, $content, $content_type, $content_encoding, $show_debug) = @_;
	
	#print STDERR "content = '" . $content . "'\n";
	#if(Encode::is_utf8($content)) {
	#	print STDERR "Encode::is_utf8 == yes\n";
	#} else {
	#	print STDERR "Encode::is_utf8 == no\n";
	#}
	
	#if(!Encode::is_utf8($content)) {
	#	$content = encode 'utf8', $content;
	#}
	
	my $http_request_build_time = get_time();
	my $request = HTTP::Request->new(POST => $url);
	#$request->header( => '""');
	$request->content($content);
	$request->content_type($content_type);
	#$content_encoding ne "" && $request->content_encoding($content_encoding);
	$content_encoding ne "" && $request->header("Content-Transfer-Encoding" => $content_encoding);

	printf STDERR "[DEBUG] build time for HTTP request: %.5f seconds\n", Time::HiRes::tv_interval( $http_request_build_time ) if $show_debug;
	
	my $http_request_time = get_time();
	my $response = $ua->request($request);
	printf STDERR "[DEBUG] actual HTTP processing time: %.5f seconds\n", Time::HiRes::tv_interval( $http_request_time ) if $show_debug;
	
	die "server: Couldn't post request" unless defined $response;
	die "server: " . $response->status_line unless $response->is_success;
	
	return $response->decoded_content;
}

# Parse XML response
sub ccd_parse_xml {
	my $response_content = shift;
	return XMLin($response_content, ForceArray => 1, KeyAttr=>'key');
}

# Parse XML ref to Perl record
sub parse_xmlref_record_to_perl {
	my $ref = shift;
	my $is_sub = shift;
	my $type = exists $ref->{type} ? "".$ref->{type} : "unknown";
	if($type eq "array") {
		my @items = ();
		foreach my $item (@{$ref->{record}}) {
			push(@items, parse_xmlref_record_to_perl($item, 1) );
		}
		return \@items;
		if( ($is_sub == 0) && exists $ref->{name}) {
			my %tmp = ();
			$tmp{$ref->{name}} = \@items;
			return \%tmp;
		} else {
			return \@items;
		}
	} elsif($type eq "object") {
		my %items = ();
		foreach my $item (@{$ref->{record}}) {
			$items{$item->{name}} = parse_xmlref_record_to_perl($item, 1);
		}
		if( ($is_sub == 0) && exists $ref->{name}) {
			my %tmp = ();
			$tmp{$ref->{name}} = \%items;
			return \%tmp;
		} else {
			return \%items;
		}
	} elsif($type eq "string") {
		if( ($is_sub == 0) && exists $ref->{name}) {
			my %tmp = ();
			$tmp{$ref->{name}} = $ref->{value};
			return \%tmp;
		} else {
			return "".$ref->{value};
		}
	} else {
		die "unknown type: $type\n";
		return undef;
	}
}

# Parse XML ref to Perl record
sub parse_xmlref_to_perl {
	my $ref = shift;
	my $session_id = "";
	my @messages = ();
	my @records = ();
	
	# Fetch and update session ID
	if(exists $ref->{session_id}) {
		$session_id = $ref->{session_id};
	}
	
	# Parse messages
	foreach my $arg (@{$ref->{message}}) {
		my %msg = ();
		$msg{'type'} = exists $arg->{type} ? "".$arg->{type} : "normal";
		if(exists $arg->{subject}) { $msg{'subject'} = "".$arg->{subject}; }
		push(@messages, \%msg);
	}
	
	# Parse records
	foreach my $arg (@{$ref->{record}}) {
		push(@records, parse_xmlref_record_to_perl($arg, 0));
	}
	
	my %results = ();
	$results{"session_id"} = $session_id;
	$results{"messages"} = \@messages;
	$results{"records"} = \@records;
	return \%results;
}


# Parse Object as single string
sub parse_object_string {
	my $parent_name = shift;
	my $object_ref = shift;
	my @options = ();
	while (my ($name, $value) = each(%{$object_ref})){
		my $type = ref($value);
		
		if($type eq "ARRAY") {
			print STDERR "ccd-client.pl:214: warning: no support for array '$parent_name.$name'\n";
		} elsif($type eq "HASH") {
			print STDERR "ccd-client.pl:216: warning: no support for object '$parent_name.$name'\n";
		} elsif(!$type) {
			push(@options, $name . "='".$value."'");
		} else {
			die "unknown type '$type' for '$parent_name.$name'\n";
		}
	}
	return join(' ', @options);
}

# Display table
sub display_table {
	my %args = @_;
	
	my $title = $args{"title"};
	my @headers = @{$args{"headers"}};
	my @rows = @{$args{"rows"}};
	
	my %cell_sizes;
	if(exists $args{"cell_sizes"}) {
		%cell_sizes = %{$args{"cell_sizes"}};
	} else {
		for my $h (@headers) {
			my $len = length $h;
			$cell_sizes{$h} = $len if (!exists $cell_sizes{$h}) || ($cell_sizes{$h} < $len);
		}
		for my $r (@rows) {
			my @names = @headers;
			for my $c (@{$r}) {
				my $name = shift @names;
				my $len = length $c;
				$cell_sizes{$name} = $len if (!exists $cell_sizes{$name}) || ($cell_sizes{$name} < $len);
			}
		}
	}
	
	my @cell_sizes;
	my @cells;
	for my $name (@headers) {
		my $format = "% ".$cell_sizes{$name}."s";
		push(@cells, sprintf($format, $name));
		push(@cell_sizes, $cell_sizes{$name});
	}
	my $line_length = sum(0, @cell_sizes) + (scalar(@cell_sizes)-1)*3;
	
	if(scalar(@rows) != 0) {
		my @lines;
		for my $key (@headers) {
			push(@lines, "-" x $cell_sizes{$key});
		}
		
		if(length($title) != 0) {
			my $left_n = int($line_length/2)-int(length($title)/2);
			my $right_n = $line_length - $left_n - length($title);
			print "/-" . ("-" x $line_length) . "-\\\n";
			print "| " . (" " x $left_n) . $title . (" " x $right_n) . " |\n";
			print "+-" . join("-+-", @lines)    . "-+\n";
		} else {
			print "/-" . ("-" x $line_length) . "-\\\n";
		}
	
		print "| " . join(" | ", @cells)  . " |\n";
		print "+-" . join("-+-", @lines)    . "-+\n";
		
		for my $row (@rows) {
			my @cell_values = @{$row};
			@cells = ();
			my @tmp_sizes = @cell_sizes;
			for my $value (@cell_values) {
				my $size = shift @tmp_sizes;
				my $format = defined($size) ? "% ".$size."s" : "%s";
				push(@cells, sprintf($format, $value));
			}
			print "| " . join(" | ", @cells) . " |\n";
		}
		print "\\-" . join("-+-", @lines) . "-/\n";
	}
}

# Parse Array
sub display_array {
	my $parent_name = shift;
	my $object_ref = shift;
	
	#my %cell_sizes;
	my @headers;
	my @rows;
	
	my $table_headers_sent = 0;
	foreach my $value (@{$object_ref}) {
		my $type = ref($value);
		
		if($type eq "ARRAY") {
			print STDERR "ccd: warning: no support for array inside array $parent_name\n";
		} elsif($type eq "HASH") {
			#print STDERR "ccd: warning: no support for object inside array $parent_name\n";
			
			my @cell_values;
			
			while (my ($cell_name, $cell_value) = each(%{$value})){
				my $cell_type = ref($cell_value);
				
				if($cell_type eq "ARRAY") {
					print STDERR "warning: no support for array $cell_name at cell in table $parent_name\n";
					$cell_value = "undefined";
				} elsif($cell_type eq "HASH") {
					$cell_value = "".parse_object_string($cell_name, $cell_value);
					#push(@cell_values, $tmp);
				} elsif(!$cell_type) {
					$cell_value = "".$cell_value;
				} else {
					print STDERR "warning: unknown cell type $cell_type at cell in table $parent_name\n";
					$cell_value = "undefined";
				}
				
				push(@headers, $cell_name) unless $table_headers_sent;
				push(@cell_values, $cell_value);
				#my $len = length $cell_value;
				#$cell_sizes{$cell_name} = $len if (!exists $cell_sizes{$cell_name}) || ($cell_sizes{$cell_name} < $len);
				#$len = length $cell_name;
				#$cell_sizes{$cell_name} = $len if (!exists $cell_sizes{$cell_name}) || ($cell_sizes{$cell_name} < $len);
			}
			
			$table_headers_sent = 1 unless $table_headers_sent;
			push(@rows, \@cell_values);
			
		} elsif(!$type) {
			#print STDOUT $value . "\n";
			push(@headers, "item") unless $table_headers_sent;
			$table_headers_sent = 1;
			my @row = ($value);
			push(@rows, \@row);
		} else {
			die "unknown type $type at row in table $parent_name\n";
		}
	}
	
	#	"cell_sizes" => \%cell_sizes, 
	display_table(
		"title"      => "$parent_name",
		"headers"    => \@headers, 
		"rows"       => \@rows,
	);
}

# Parse Object
sub display_object {
	my $parent_name = shift;
	my $object_ref = shift;
	
	my @headers = ("key", "value");
	my @rows;
	
	while (my ($name, $value) = each(%{$object_ref})){
		my $type = ref($value);
		if($type eq "ARRAY") {
			display_array($name, $value);
		} elsif($type eq "HASH") {
			display_object($name, $value);
		} elsif(!$type) {
			#printf STDOUT "%s = %s\n", $name, $value;
			my @row = ($name, $value);
			push(@rows, \@row);
		} else {
			die "unknown type '$type' for '$parent_name.$name'\n";
		}
	}
	
	display_table(
		"title"      => "$parent_name",
		"headers"    => \@headers, 
		"rows"       => \@rows,
	);
}

# Output CLI style
sub display {
	my $ref = shift;
	
	my $exit_status = 0;
	
	# Parse messages
	foreach my $arg (@{$ref->{messages}}) {
		my $type = exists $arg->{type} ? $arg->{type} : "normal";
		my $subject;
		if(exists $arg->{subject}) {
			$subject = $arg->{subject};
		}
		
		if($type eq "error") {
			die "$subject\n";
		} elsif($type eq "warning") {
			print STDERR 'ccd: warning: ' . $subject . "\n";
		} else {
			if(exists $arg->{subject}) { print $subject; }
			print "\n";
		}
	}
	
	# Parse records
	foreach my $arg (@{$ref->{records}}) {
		my $type = ref($arg);
		if($type eq "ARRAY") {
			display_array("", $arg);
		} elsif($type eq "HASH") {
			display_object("", $arg);
		} elsif(!$type) {
			printf STDOUT "\n%s\n", $arg;
		} else {
			die "unknown type $type in record\n";
		}
	}
	
	return $exit_status;
}

# Run CCD command
sub do_ccd_command {
	my %args = @_;
	my $ua = $args{"ua"};
	my $ccd_url = exists($args{"url"}) ? $args{"url"} : "";
	my $session_id = exists($args{"session_id"}) ? $args{"session_id"} : "";
	my $send_type = exists($args{"send_type"}) ? $args{"send_type"} : "json";
	my $output_type = exists($args{"output_type"}) ? $args{"output_type"} : "plain";
	my $show_debug = exists($args{"show_debug"}) ? $args{"show_debug"} : 0;
	my $OUT = $args{"OUT"};
	
	# Send JSON request
	my $req;
	if($send_type eq "json") {
		print $OUT "[DEBUG] Using JSON requests\n" if $show_debug;
		use JSON;
		
		# Pre encoding
		my $pre_encoding_time = get_time();
		my $json_request = encode_qp(encode_json $args{"requests"});
		printf $OUT "[DEBUG] request encoding time: %.5f seconds\n", Time::HiRes::tv_interval( $pre_encoding_time ) if $show_debug;
		print $OUT "[DEBUG] json_request='$json_request'\n" if $show_debug;
		
		# HTTP POST
		my $http_time = get_time();
		my $response_content = ccd_http_post($ua, $ccd_url, $json_request, "application/json; charset=utf-8", "quoted-printable", $show_debug);
		printf $OUT "[DEBUG] HTTP processing time: %.5f seconds\n", Time::HiRes::tv_interval( $http_time ) if $show_debug;
		print $OUT "[DEBUG] json_reply='$response_content'\n" if $show_debug;
		
		# POST decoding
		my $post_decoding_time = get_time();
		$req = decode_json $response_content;
		printf $OUT "[DEBUG] Reply decoding time: %.5f seconds\n", Time::HiRes::tv_interval( $post_decoding_time ) if $show_debug;
		
	} elsif($send_type eq "xml") {
		print $OUT "[DEBUG] Using XML requests\n" if $show_debug;
		use XML::Simple qw(:strict);
		my $xml_request = build_xml_request($session_id, @{$args{"requests"}} );
		print $OUT "[DEBUG] xml_request='$xml_request'\n" if $show_debug;
		my $response_content = ccd_http_post($ua, $ccd_url, $xml_request, "application/xml; charset=utf-8", "", $show_debug);
		print $OUT "[DEBUG] response_content='$response_content'\n" if $show_debug;
		my $ref = ccd_parse_xml($response_content);
		$req = parse_xmlref_to_perl($ref);
	} else {
		die "unknown send type: $send_type";
	}
	
	# Fetch and update session ID
	if(exists $req->{session_id}) {
		$session_id = $req->{session_id};
	} else {
		$session_id = "";
	}
	
	# Output results
	my $exit_status = 0;
	if($output_type eq "json") {
		my $json_reply = encode_json $req;
		print $json_reply . "\n";
		# FIXME: There could be exit_status parsed
	} else {
		$exit_status = display($req);
	}
	
	## Print debug
	#print $OUT "[DEBUG] command = '$command'\n";
	#print $OUT "[DEBUG] options = '" . join("', '", keys(%options) ) ."'\n";
	#print $OUT "[DEBUG] session_id = $session_id\n";
	#print $OUT "[DEBUG] xml_request = '$xml_request'\n";
	#print $OUT "[DEBUG] response = '$response_content'\n";
	
	return ($exit_status, $session_id);
}

# Build request from command line arguments
sub parse_argv {
	my %sub_args = @_;
	my $session_id = $sub_args{"session_id"};
	my @line = @{$sub_args{"line"}};
	my %defaults = %{$sub_args{"defaults"}};
	
	my $codeset = langinfo(CODESET);
	@line = map { decode $codeset, $_ } @line;
	
	my %request = build_perl_request($session_id, @line);
	my %args;
	
	my @local_args = @{$request{"local_args"}};
	$args{"url"} = exists($defaults{"url"}) ? $defaults{"url"} : $Config::CCD_URL;
	$args{"send"} = exists($defaults{"send"}) ? $defaults{"send"} : "json";
	$args{"output"} = exists($defaults{"output"}) ? $defaults{"output"} : "plain";
	$args{"debug"} = exists($defaults{"debug"}) ? $defaults{"debug"} : 0;
	$args{"shell"} = exists($defaults{"shell"}) ? $defaults{"shell"} : 0;
	foreach my $arg (@local_args) {
		if($arg =~ /^--url=(.+)$/) { $args{"url"} = $1; }
		if($arg eq "--xml") { $args{"send"} = "xml"; }
		if($arg eq "--json") { $args{"output"} = "json"; }
		if($arg eq "--debug") { $args{"debug"} = 1; }
		if($arg eq "--shell") { $args{"shell"} = 1; }
		if($arg =~ /^--read:([^:]+)=\@(.+)$/) {
			my $key = $1;
			my $file = $2;
			open(HANDLE, "$file"); 
			my $value = join("", <HANDLE>);
			close(HANDLE);
			$request{"options"}->{$key} = $value;
		}
	}
	delete $request{"local_args"};
	
	my @requests;
	push(@requests, \%request) unless $request{"command"} eq "";
	
	my %result;
	$result{"args"} = \%args;
	$result{"requests"} = \@requests;
	return %result;
}

# Get time
sub get_time {
	use Time::HiRes;
	return [ Time::HiRes::gettimeofday( ) ];
}

# Split string by content
sub content_split {
	my $line = shift;
	my @regexes;
	for my $format (@_) {
		push(@regexes, qr/^($format)/);
	}
	
	my $cell = "";
	my @parts;
	CELL: while($line ne "") {
		#print $OUT "[DEBUG] \$line = '$line'\n";
		for my $regex (@regexes) {
			if($line =~ /^(\s+)/) {
				push(@parts, $cell);
				$cell = "";
				$line = substr($line, (length $1) );
				next CELL;
			}
			if($line =~ $regex) {
				#print STDERR "[DEBUG] \$1 = '$1'\n";
				#print STDERR "[DEBUG] \$2 = '$2'\n";
				$cell .= $2;
				$line = substr($line, (length $1) );
				next CELL;
			}
		}
		die "Could not parse cell from: '$line'";
	}
	push(@parts, $cell);
	return @parts;
}

# Main Block
eval {
	
	# Build user agent
	my $ua = LWP::UserAgent->new;
	$ua->timeout($Config::BROWSER_TIMEOUT);
	$ua->agent('ccd-client/0.4');

	# Enable Keep-Alive
	use LWP::ConnCache;
	my $cache = $ua->conn_cache(LWP::ConnCache->new());
	$ua->conn_cache->total_capacity(undef);
	
	# Load session_id from file
	my $session_id = "";
	if(defined($Config::CCD_SESSION_ID_FILE)) { load_session_id($Config::CCD_SESSION_ID_FILE); }
	
	# Build JSON request from shell
	my %default_args;
	my %parsed = parse_argv( "session_id" => $session_id, "line" => \@ARGV, "defaults"=>\%default_args);
	my %args = %{$parsed{"args"}};
	$args{"shell"} = 1 if scalar(@{$parsed{"requests"}}) == 0;
	
	my $exit_status = 0;
	
	if($args{"shell"}) {
		
		#binmode STDIN, ":utf8";
		use Term::ReadLine;
		my $term = Term::ReadLine->new("CCD shell");
		my $prompt = "ccd> ";
		my $OUT = $term->OUT || \*STDOUT;
		#binmode $OUT, ":utf8";
		
		$term->Attribs->ornaments(0) if UNIVERSAL::can($term->Attribs, 'isa');
		
		my $lastline = "";
		SHELL: while ( defined (my $line = $term->readline($prompt)) ) {
			
			my $start_time = get_time();
			
			$line =~ s/^\s+//;
			$line =~ s/\s+$//;
			
			$line = "/quit" if $line =~ /^(quit|exit)$/;
			my @line = content_split($line, "\"([^\"]*)\"", "'([^']*)'", "([^\t '\"]+)");
			print $OUT "[DEBUG] \@line    = ('" . join("', '", @line) . "')\n" if $args{"debug"};
			
			
			if($line =~ /^\//) {
				my $command = substr(shift(@line), 1);
				last SHELL if ($command eq "exit") || ($command eq "quit");
				if($command eq "version") {
					print $OUT "ccd-client:  " . '$Id: ccd-client.pl 13913 2010-08-23 19:18:29Z jheusala $' . "\n";
					print $OUT "uses:        " . $term->ReadLine . "\n";
				}
				if($command eq "status") {
					print $OUT "URL: " . $args{"url"} . "\n";
				}
				if($command eq "config") {
					print $OUT "CCD_URL:             " . $Config::CCD_URL . "\n" if defined $Config::CCD_URL;
					print $OUT "HOME:                " . $Config::HOME . "\n" if defined $Config::HOME;
					print $OUT "CCD_CONFIG_DIR:      " . $Config::CCD_CONFIG_DIR . "\n" if defined $Config::CCD_CONFIG_DIR;
					print $OUT "CCD_SESSION_ID_FILE: " . $Config::CCD_SESSION_ID_FILE . "\n" if defined $Config::CCD_SESSION_ID_FILE;
				}
				if($command eq "dummy") {
					print $OUT "\$command = '$command'\n";
					print $OUT "\@line    = ('" . join("', '", @line) . "')\n";
				}
			} elsif($line ne "") {
				eval {
					my %line = parse_argv( "session_id" => $session_id, "line"=>\@line, "defaults"=>\%args );
					my %line_args = %{$line{"args"}};
					my @requests = @{$line{"requests"}};
					
					# Run command
					my $request_start_time = get_time();
					my($current_exit_status, $new_session_id) = do_ccd_command(
						"OUT" => $OUT,
						"ua" => $ua,
						"url" => $line_args{"url"},
						"send_type" => $line_args{"send"},
						"output_type" => $line_args{"output"},
						"show_debug" => $line_args{"debug"},
						"requests" => \@requests,
					);
					$session_id = $new_session_id;
					$exit_status = $current_exit_status;
					
					my $request_elapsed_time = Time::HiRes::tv_interval( $request_start_time );
					printf $OUT "[DEBUG] request time: %.5f seconds\n", $request_elapsed_time if $args{"debug"};
					
					1;
				} or do {
					print $OUT "error: $@\n";
				};
				
			}
			
			# Add only unique lines to history, ignore otherwise
			if($lastline ne $line) {
				$term->addhistory($line);
				$lastline = $line;
			}
			
			my $elapsed_time = Time::HiRes::tv_interval( $start_time );
			printf $OUT "[DEBUG] total time: %.5f seconds\n", $elapsed_time if $args{"debug"};
		}
		
	} else {
		# Run single command
		my @requests = @{$parsed{"requests"}};
		my($current_exit_status, $new_session_id) = do_ccd_command(
			"OUT" => \*STDOUT,
			"ua" => $ua,
			"url" => $args{"url"},
			"send_type" => $args{"send"},
			"output_type" => $args{"output"},
			"show_debug" => $args{"debug"},
			"requests" => \@requests,
		);
		$session_id = $new_session_id;
		$exit_status = $current_exit_status;
	}
	
	# Save session_id to file
	if($session_id ne "") {
		mkdir $Config::CCD_CONFIG_DIR unless (!defined($Config::CCD_CONFIG_DIR)) || -e $Config::CCD_CONFIG_DIR;
		save_session_id($Config::CCD_SESSION_ID_FILE, $session_id) if defined $Config::CCD_SESSION_ID_FILE;
	} else {
		unlink( $Config::CCD_SESSION_ID_FILE ) if defined($Config::CCD_SESSION_ID_FILE) && -e $Config::CCD_SESSION_ID_FILE;
	}
	exit $exit_status;
	
	1;
} or do {
	print STDERR "ccd: error: $@\n";
	exit 1
};

# EOF
