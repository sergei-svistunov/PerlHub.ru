package PerlHub::Application::Model::PackageSeries;

use qbit;

use base qw(QBit::Application::Model::DBManager);

use File::Path qw(make_path);

__PACKAGE__->register_rights(
    [
        {
            name        => 'package_series',
            description => sub {gettext('Rights for series')},
            rights      => {
                package_series_view => d_gettext('Right to view series'),
                package_series_add  => d_gettext('Right to add series'),
            },
        }
    ]
);

__PACKAGE__->model_accessors(
    db              => 'PerlHub::Application::Model::DB',
    package_indexer => 'PerlHub::Application::Model::PackageIndexer'
);

__PACKAGE__->model_fields(
    id          => {db => TRUE, pk      => TRUE, default => TRUE,},
    name        => {db => TRUE, default => TRUE,},
    description => {db => TRUE,},
    outdated    => {db => TRUE,},
);

__PACKAGE__->model_filter(
    db_accessor => 'db',
    fields      => {
        id          => {type => 'number'},
        name        => {type => 'text'},
        description => {type => 'text'},
        outdated    => {type => 'boolean'},
    }
);

sub query {
    my ($self, %opts) = @_;

    throw Exception::Denied unless $self->check_rights('package_series_view');

    return $self->db->query->select(
        table  => $self->db->package_series,
        fields => $opts{'fields'}->get_db_fields(),
        filter => $opts{'filter'},
    );
}

sub add {
    my ($self, %opts) = @_;

    throw Exception::Denied unless $self->check_rights('package_series_add');

    my @fields = qw(name description);

    my @missed_required_fields = grep {!defined($opts{$_})} @fields;
    throw Exception::BadArguments ngettext(
        'Missed required parameter "%s"',
        'Missed required parameters: %s',
        scalar(@missed_required_fields),
        join(', ', @missed_required_fields)
    ) if @missed_required_fields;

    my $id;
    try {
        $self->db->transaction(
            sub {
                $id = $self->db->package_series->add({map {$_ => $opts{$_}} @fields});

                my $var_path = $self->get_option('packages_dir') . '/var';
                make_path($var_path) unless -d $var_path;

                my $packages_path = $self->get_option('packages_path') . "/$opts{'name'}";
                make_path($packages_path) unless -d $packages_path;

                my @archs =
                  map {$_->{'name'}} @{$self->db->package_arch->get_all(fields => [qw(name)])};
                push(@archs, 'source');

                $self->package_indexer->changed_archs($packages_path, $var_path, $opts{'name'}, @archs);
            }
        );
    }
    catch Exception::DB::DuplicateEntry with {
        throw Exception::BadArguments gettext('"%s" is already exists', $opts{'name'});
    };

    return $id;
}

TRUE;
