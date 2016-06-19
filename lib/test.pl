#!/usr/bin/perl

use lib qw(../lib);

use qbit;

use PerlHub::Application;

my $app = PerlHub::Application->new();

$app->pre_run();

#ldump($app->package_source->get(174, fields => [qw(id name version builds)]));
#
#ldump(
#    $app->package_build->get(
#        {
#            'source_id' => '174',
#            'arch_id'   => '1',
#            'series_id' => '7',
#        },
#        fields => [qw(source_id arch_id series_id multistate multistate_name build_depends)]
#    )
#);
#exit;
#
#$app->db->package_build->edit(
#    {
#        'source_id' => '174',
#        'arch_id'   => '1',
#        'series_id' => '7',
#    },
#    {multistate => 0}
#);
#
#ldump($app->package_build->take_build());


ldump($app->db->package_series->get_all());
exit;
$app->package_indexer->publish_all(force_all => TRUE);
exit;

ldump({
            arches => [map {$_->{'name'}} @{$app->db->package_arch->get_all(fields => [qw(name)])}],
            series => [
                map {$_->{'name'}}
                  @{$app->db->package_series->get_all(fields => [qw(name)], filter => {outdated => 0})}
            ],
            othermirrors => [
                'deb http://packages.perlhub.ru {{SERIES}}/all/', 'deb http://packages.perlhub.ru {{SERIES}}/{{ARCH}}/',
            ],
            components => [$app->dist_package->get_components()],
        });
exit;

my $build_id = {
    'source_id'       => '174',
    'build_depends'   => 'debhelper (>= 8.0.0), perl, libqbit-perl',
    'arch_name'       => 'all',
    'package_name'    => 'libqbit-class-perl',
    'series_id'       => '7',
    'series_name'     => 'xenial',
    'source_arc_url'  => 'http://127.0.0.1:8000/_source/libqbit-class-perl_0.3/libqbit-class-perl_0.3.tar.gz',
    'arch_id'         => 1,
    'package_version' => '0.3'
};
