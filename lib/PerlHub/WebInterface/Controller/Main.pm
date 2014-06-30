package PerlHub::WebInterface::Controller::Main;

use qbit;

use base qw(PerlHub::WebInterface::Controller);

__PACKAGE__->model_accessors(
    db             => 'PerlHub::Application::Model::DB',
    gpg            => 'PerlHub::Application::Model::GPG',
    package_source => 'PerlHub::Application::Model::PackageSource',
    package_build  => 'PerlHub::Application::Model::PackageBuild',
);

sub page : CMD : DEFAULT {
    my ($self) = @_;

    $self->package_source->get_all(fields => ['id'], limit => 0, calc_rows => TRUE);
    my $total_sources = $self->package_source->found_rows();

    return $self->from_template(
        'main/page.tt2',
        vars => {
            series => $self->db->package_series->get_all(
                fields   => [qw(id name description)],
                order_by => ['name']
            ),
            arches => $self->db->package_arch->get_all(
                fields   => [qw(name description)],
                filter   => [name => '<>' => \'all'],
                order_by => ['id']
            ),
            gpg_sign_pub_key          => $self->gpg->get_sign_pub_key(),
            total_sources             => $total_sources,
            builded_cnt               => $self->package_build->get_series_bulded_cnt(),
            last_uploaded_source_pkgs => $self->package_source->get_all(
                fields   => [qw(name version upload_dt)],
                order_by => [[upload_dt => TRUE]],
                limit    => 10
            ),
            last_builded_pkgs => $self->package_build->get_all(
                fields   => [qw(package_name package_version series_name arch_name)],
                filter   => [multistate => '=' => 'completed'],
                order_by => [[source_id => TRUE], [series_id => TRUE], [arch_id => TRUE]],
                limit    => 10
            ),
        }
    );
}

TRUE;
