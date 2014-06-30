package PerlHub::Application::Model::DB;

use qbit;

use base qw(
  PerlHub::Application::Model::DB::User
  PerlHub::Application::Model::DB::Package
  QBit::Application::Model::DB::mysql::RBAC
);

TRUE;
