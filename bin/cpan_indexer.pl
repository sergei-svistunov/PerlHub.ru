#!/usr/bin/perl

use qbit;

use File::Find;
use File::Temp qw(tempdir);
use File::Path qw(remove_tree);
use CPAN::DistnameInfo;
use Archive::Any;
use DBI;
use PPI;

my $WORKER_CNT   = 8;
my $CPAN_DIR     = '/home/svistunov/cpan/cpan';
my $CPAN_ARC_DIR = "$CPAN_DIR/authors/id";

my @files;

find(
    sub {
        push(@files, $File::Find::name) if /\.(tgz|tbz|tar[\._-]gz|tar\.bz2|tar\.Z|zip|7z)$/;
    },
    $CPAN_ARC_DIR
);

my @pids;
foreach my $fn (@files) {
    if (@pids >= $WORKER_CNT) {
        my $pid = waitpid(-1, 0);
        @pids = grep {$_ != $pid} @pids;
    }
    if (my $pid = fork()) {
        push(@pids, $pid);
    } else {
        index_distr($fn);
        exit;
    }
}

waitpid($_, 0) foreach @pids;

sub index_distr {
    my ($fn) = @_;

    my $dir = tempdir(DIR => '/tmp/ramdisk');
    chdir($dir);

    my $dist_info = CPAN::DistnameInfo->new($fn);
    my $store_fn  = $fn;
    $store_fn =~ s/^$CPAN_ARC_DIR\///;

    my $dbh = DBI->connect('DBI:mysql:database=cpan', 'root', '', {PrintError => FALSE})
      || throw $DBI::errstr;

    my $res = $dbh->do('INSERT INTO cpan_release(`name`, `version`, `author`, `filename`) VALUES(?, ?, ?, ?)',
        {}, $dist_info->dist(), $dist_info->version(), $dist_info->cpanid(), $store_fn);

    unless ($res) {
        if ($DBI::err == 1062) {
            return;
        } else {
            throw $DBI::errstr;
        }
    }

    my ($release_id) = $dbh->selectrow_array('select LAST_INSERT_ID()');

    l $$, $release_id, $store_fn;

    my $archive = Archive::Any->new($fn);
    if ($archive) {
        try {
            $archive->extract();
            chdir([$archive->files()]->[0]);
            undef($archive);
            find(
                sub {
                    return unless /\.pm$/;

                    my $pm_short_fn = $_;
                    my $pm_fn       = $File::Find::name;
                    $pm_fn =~ s/^\.\///;

                    if (my $doc = PPI::Document->new($pm_short_fn)) {
                        my $pkg_states = $doc->find('PPI::Statement::Package');

                        $dbh->do('INSERT INTO cpan_release_provide VALUES(?, ?, ?)', {}, $release_id, $_, $pm_fn)
                          foreach map {$_->namespace} @{$pkg_states || []};
                    } else {
                        l($pm_fn, PPI::Document->errstr);
                    }
                },
                './'
            );
        }
        catch {
            l shift->message();
        };
    }

    chdir('/tmp');
    remove_tree($dir);
}
