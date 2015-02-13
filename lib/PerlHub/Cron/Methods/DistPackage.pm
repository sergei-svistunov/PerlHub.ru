package PerlHub::Cron::Methods::DistPackage;

use qbit;

use base qw(QBit::Cron::Methods);

__PACKAGE__->model_accessors(dist_package => 'PerlHub::Application::Model::DistPackage');

sub update : CRON('*/20 * * * *') : LOCK {
    my ($self) = @_;

    $self->dist_package->update();
}

TRUE;
