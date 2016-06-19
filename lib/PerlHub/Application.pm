package PerlHub::Application;

use qbit;

use base qw(QBit::Application);

use PerlHub::Application::Model::DB accessor => 'db';

use PerlHub::Application::Model::Users accessor => 'users';

use QBit::Application::Model::RBAC::DB accessor => 'rbac';
use QBit::Application::Model::SendMail accessor => 'sendmail';

use PerlHub::Application::Model::GPG accessor                     => 'gpg';
use PerlHub::Application::Model::PackageSource accessor           => 'package_source';
use PerlHub::Application::Model::PackageBuild accessor            => 'package_build';
use PerlHub::Application::Model::PackageBuildWaitDepends accessor => 'package_build_wait_depends';
use PerlHub::Application::Model::PackageIndexer accessor          => 'package_indexer';
use PerlHub::Application::Model::DistPackage accessor             => 'dist_package';
use PerlHub::Application::Model::PackageSeries accessor           => 'package_series';

try {
    __PACKAGE__->use_config('PerlHub/Application.cfg');
};

sub init {
    my ($self) = @_;

    $self->SUPER::init();

    unless ($ENV{'NO_PKG_INEXER_INIT'}) {
        $self->pre_run();
        try {
            $self->package_indexer->initialize_dirs();
        }
        catch {
            l(shift->message());
        };
        $self->post_run();
    }
}

TRUE;
