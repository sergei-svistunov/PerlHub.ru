package PerlHub::Cron::Methods::PackageIndexer;

use qbit;

use base qw(QBit::Cron::Methods);

__PACKAGE__->model_accessors(package_indexer => 'PerlHub::Application::Model::PackageIndexer');

sub publish_all : CRON('* * * * *') : LOCK {
    my ($self) = @_;

    $self->package_indexer->publish_all();
}

TRUE;
