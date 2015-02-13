package PerlHub::Cron::Methods::PackageSource;

use qbit;

use base qw(QBit::Cron::Methods);

__PACKAGE__->model_accessors(package_source => 'PerlHub::Application::Model::PackageSource');

sub schedule_build : CRON('* * * * *') : LOCK {
    my ($self) = @_;

    my $dput_dir = $self->get_option(dput_path => '/opt/perlhub/dput_upload');

    opendir(my $dh, $dput_dir) || throw "Cannot open dir $dput_dir: $!";
    my @changes_files = grep {/\.changes$/} readdir($dh);
    closedir($dh);

    try {
        $self->package_source->add("$dput_dir/$_");
    } catch {
        l shift->message();
    }
    foreach @changes_files;
}

TRUE;
