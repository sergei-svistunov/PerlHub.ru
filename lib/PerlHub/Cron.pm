package PerlHub::Cron;

use qbit;

use base qw(QBit::Cron PerlHub::Application);

use PerlHub::Cron::Methods::PackageSource path  => 'package_source';
use PerlHub::Cron::Methods::PackageIndexer path => 'package_indexer';

TRUE;
