package Net::Amazon::S3::Client;

use Moose 0.85;
use HTTP::Status qw(status_message);
use MooseX::StrictConstructor 0.16;
use Moose::Util::TypeConstraints;

use Net::Amazon::S3::Error::Handler::Confess;

# ABSTRACT: An easy-to-use Amazon S3 client

type 'Etag' => where { $_ =~ /^[a-z0-9]{32}(?:-\d+)?$/ };

has 's3' => ( is => 'ro', isa => 'Net::Amazon::S3', required => 1 );

has error_handler_class => (
    is => 'ro',
    lazy => 1,
    default => 'Net::Amazon::S3::Error::Handler::Confess',
);

has error_handler => (
    is => 'ro',
    lazy => 1,
    default => sub { $_[0]->error_handler_class->new (s3 => $_[0]->s3) },
);

around BUILDARGS => sub {
	my ($orig, $class) = (shift, shift);
	my $args = $class->$orig (@_);

	unless (exists $args->{s3}) {
		my $error_handler_class = delete $args->{error_handler_class};
		my $error_handler       = delete $args->{error_handler};
		$args = {
			(error_handler_class => $error_handler_class) x!! defined $error_handler_class,
			(error_handler       => $error_handler      ) x!! defined $error_handler,
			s3 => Net::Amazon::S3->new ($args),
		}
	}

	$args;
};

__PACKAGE__->meta->make_immutable;

sub bucket_class { 'Net::Amazon::S3::Client::Bucket' }

sub buckets {
    my $self = shift;
    my $s3   = $self->s3;

    my $response = $self->_perform_operation (
        'Net::Amazon::S3::Operation::Buckets::List',
    );

    return unless $response->is_success;

    my $owner_id = $response->owner_id;
    my $owner_display_name = $response->owner_displayname;

    my @buckets;
    foreach my $bucket ($response->buckets) {
        push @buckets, $self->bucket_class->new (
			client             => $self,
			name               => $bucket->{name},
			creation_date      => $bucket->{creation_date},
			owner_id           => $owner_id,
			owner_display_name => $owner_display_name,
		);

    }
    return @buckets;
}

sub create_bucket {
    my ( $self, %conf ) = @_;

    my $bucket = $self->bucket_class->new(
        client => $self,
        name   => $conf{name},
    );
    $bucket->_create(
        acl_short           => $conf{acl_short},
        location_constraint => $conf{location_constraint},
    );
    return $bucket;
}

sub bucket {
    my ( $self, %conf ) = @_;
    return $self->bucket_class->new(
        client => $self,
        %conf,
    );
}

sub _send_request_raw {
    my ( $self, $http_request, $filename ) = @_;

	$http_request = $http_request->http_request
		if $http_request->$Safe::Isa::_isa ('Net::Amazon::S3::Request');

	return Net::Amazon::S3::Response->new (
		http_response => scalar $self->s3->ua->request( $http_request, $filename ),
	);
}

sub _send_request {
    my ( $self, $http_request, $filename ) = @_;

    my $http_response = $self->_send_request_raw( $http_request, $filename );

	$self->error_handler->handle_error ($http_response);

    return $http_response;
}

sub _send_request_content {
    my ( $self, $http_request, $filename ) = @_;
    my $http_response = $self->_send_request( $http_request, $filename );
    return $http_response->content;
}

sub _send_request_xpc {
    my ( $self, $http_request, $filename ) = @_;
    my $http_response = $self->_send_request( $http_request, $filename );

    return $http_response->xpath_context;
}

=head2 _perform_operation

Refer L<Net::Amazon::S3/_perform_operation

Method supports additional parameters

=over

=item filename

Filename callback (see L<LWP::UserAgent> for details) (optional)

=back

=cut

sub _perform_operation {
	my ($self, $operation, %params) = @_;

	my $error_handler = delete $params{error_handler};
	$error_handler = $self->error_handler unless defined $error_handler;

    my $request_class  = $operation . '::Request';
    my $response_class = $operation . '::Response';
    my $filename       = delete $params{filename};

    my $request  = $request_class->new (s3 => $self->s3, %params);
    my $response = $self->_send_request_raw ($request->http_request, $filename);
    $response    = $response_class->new (http_response => $response->http_response);

    $error_handler->handle_error ($response);

    return $response;
}

1;

__END__

=for test_synopsis
no strict 'vars'

=head1 SYNOPSIS

	# Build Client instance
	my $client = Net::Amazon::S3::Client->new (
		# accepts all Net::Amazon::S3's arguments
		aws_access_key_id     => $aws_access_key_id,
		aws_secret_access_key => $aws_secret_access_key,
		retry                 => 1,
	);

	# or reuse an existing S3 connection
	my $client = Net::Amazon::S3::Client->new (s3 => $s3);

	# list all my buckets
	# returns a list of L<Net::Amazon::S3::Client::Bucket> objects
	my @buckets = $client->buckets;
	foreach my $bucket (@buckets) {
		print $bucket->name . "\n";
	}

	# create a new bucket
	# returns a L<Net::Amazon::S3::Client::Bucket> object
	my $bucket = $client->create_bucket(
		name                => $bucket_name,
		acl_short           => 'private',
		location_constraint => 'us-east-1',
	);

	# or use an existing bucket
	# returns a L<Net::Amazon::S3::Client::Bucket> object
	my $bucket = $client->bucket( name => $bucket_name );

=head1 DESCRIPTION

The L<Net::Amazon::S3> module was written when the Amazon S3 service
had just come out and it is a light wrapper around the APIs. Some
bad API decisions were also made. The
L<Net::Amazon::S3::Client>, L<Net::Amazon::S3::Client::Bucket> and
L<Net::Amazon::S3::Client::Object> classes are designed after years
of usage to be easy to use for common tasks.

These classes throw an exception when a fatal error occurs. It
also is very careful to pass an MD5 of the content when uploaded
to S3 and check the resultant ETag.

WARNING: This is an early release of the Client classes, the APIs
may change.

=head1 CONSTRUCTOR

=over

=item s3

L<< Net::Amazon::S3 >> instance

=item error_handler_class

Error handler class name (package name), see L<< Net::Amazon::S3::Error::Handler >>
for more. Overrides one available in C<s3>.

Default: L<< Net::Amazon::S3::Error::Handler::Confess >>

=item error_handler

Instance of error handler class.

=head1 METHODS

=head2 new

L<Net::Amazon::S3::Client> can be constructed two ways.

Historically it wraps S3 API instance

	use Net::Amazon::S3::Client;

	my $client = Net::Amazon::S3::Client->new (
		s3 => .... # Net::Amazon::S3 instance
	);

=head2 new (since v0.92)

Since v0.92 explicit creation of S3 API instance is no longer necessary.
L<Net::Amazon::S3::Client>'s constructor accepts same parameters as L<Net::Amazon::S3>

	use Net::Amazon::S3::Client v0.92;

	my $client = Net::Amazon::S3::Client->new (
		aws_access_key_id     => ...,
		aws_secret_access_key => ...,
		...,
	);

=head2 buckets

  # list all my buckets
  # returns a list of L<Net::Amazon::S3::Client::Bucket> objects
  my @buckets = $client->buckets;
  foreach my $bucket (@buckets) {
    print $bucket->name . "\n";
  }

=head2 create_bucket

  # create a new bucket
  # returns a L<Net::Amazon::S3::Client::Bucket> object
  my $bucket = $client->create_bucket(
    name                => $bucket_name,
    acl_short           => 'private',
    location_constraint => 'us-east-1',
  );

=head2 bucket

  # or use an existing bucket
  # returns a L<Net::Amazon::S3::Client::Bucket> object
  my $bucket = $client->bucket( name => $bucket_name );

=head2 bucket_class

  # returns string "Net::Amazon::S3::Client::Bucket"
  # subclasses will want to override this.
  my $bucket_class = $client->bucket_class

