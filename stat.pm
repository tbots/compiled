package stat;

our %cfg=( #config
	host=>"stat.clickfrog.ru",
	port=>"83",
	workers=>4,
	msgcount=>5
);

our $VERSION = '1.00';

$cfg{variables}=[split /\n/,trim(
"
QUERY_STRING
REQUEST_METHOD
CONTENT_TYPE
CONTENT_LENGTH
SCRIPT_NAME
REQUEST_URI
DOCUMENT_URI
DOCUMENT_ROOT
SERVER_PROTOCOL
REMOTE_ADDR
REMOTE_PORT
REMOTE_USER
SERVER_ADDR
SERVER_PORT
SERVER_NAME
SERVER_ADMIN
REQUEST_TIME
HTTP_ACCEPT
HTTP_ACCEPT_CHARSET
HTTP_ACCEPT_ENCODING
HTTP_ACCEPT_LANGUAGE
HTTP_CONNECTION
HTTP_HOST
HTTP_REFERER
HTTP_X_FORWARDED_FOR
HTTP_USER_AGENT
HTTPS
AUTH_TYPE
PATH_INFO
")];

select(STDERR);
$|=1;

use strict;
use warnings;

use threads;
use Thread::Queue;

use nginx;

use JSON;
use URI::Escape;
use Digest::SHA1;
use IO::Socket;

#use Data::Dump qw(dump);

use FindBin qw($Bin);
use lib "$Bin/../";

our $q=Thread::Queue->new();
my @thr;

sub genAndSend {
	my $socket=IO::Socket::INET->new(
		Proto=>'udp',
		PeerPort=>$cfg{port},
		PeerAddr=>$cfg{host}
	);
	while (my $item=$q->dequeue()){
		my %data=%{$item};

		my $msg=&makeMsg(\%data);

		for (my $i=0;$i<$cfg{msgcount};$i++){
			$socket->send($msg);
		}
	}
}

sub makeMsg {
	my %data=%{$_[0]};

	my $ctx=Digest::SHA1->new;	
	my $json = JSON->new->allow_nonref->encode(\%data); 
	# OR  my $json=encode_json(\%data);
	$ctx->add($json);
	my $msgid=substr(time(),-8).substr($ctx->hexdigest,0,8);
	my $msg="CFSTAT#".$msgid."[header=".uri_escape($json)."]END";

	return $msg;
}

sub handler {
	my $r=shift;

	push (@thr,threads->create(\&genAndSend)) while (@thr<$cfg{workers});

	my %data;
	foreach my $i (@{$cfg{variables}}){
		my $var=$r->variable(lc($i));
		$data{$i}=$var if ($var);
	}
	$q->enqueue(\%data);
	#$r->send_http_header('text/plain');
	#$r->print(&makeMsg(\%data));
	#return OK;
	return 474;
}

sub trim {
	@_ = $_ if not @_ and defined wantarray;
	@_ = @_ if defined wantarray;
	for (@_ ? @_ : $_) { s/^\s+//, s/\s+$// }
	return wantarray ? @_ : $_[0] if defined wantarray;
}

1;

__END__
