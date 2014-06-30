#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use open qw(:std :utf8);

use FindBin qw($Bin);
use Template;

my $port = 8000;

my $pwd = `pwd`;
chomp($pwd);

if ($pwd =~ /(\d+)$/) {
    $port = $1;
} else {
    while (!$port) {
        print "Port: ";
        $port = int(<STDIN>);
    }
}

my $apache_dir = $Bin;
$apache_dir =~ s/\/beta$//;

my $tt = Template->new(
    INCLUDE_PATH => $Bin,
    VARIABLES    => {
        dir     => $apache_dir,
        port    => $port,
        sslport => $port + 400,
    },
);

foreach my $name (qw(init.sh nginx.conf Application.cfg WebInterface.cfg)) {
    $tt->process("$name.tt2", {}, "$Bin/$name") || die $tt->error();
}
