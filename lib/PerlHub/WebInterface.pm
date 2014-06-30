package PerlHub::WebInterface;

use qbit;

use base qw(PerlHub::Application QBit::WebInterface::FastCGI);

use PerlHub::WebInterface::Controller::Main path    => 'main';
use PerlHub::WebInterface::Controller::User path    => 'user';
use PerlHub::WebInterface::Controller::Package path => 'package';
use PerlHub::WebInterface::Controller::API path     => 'api';
use QBit::WebInterface::Controller::RBAC path       => 'rbac';

__PACKAGE__->use_config('PerlHub/WebInterface.cfg');

$QBit::WebInterface::Request::MAX_POST_REQEST_SIZE = 50 * 1024 * 1024;

sub default_cmd {'main'}

sub pre_cmd {
    my ($self) = @_;

    my $session = $self->request->cookie('qs', []);
    if (defined($session) && $self->users->check_session(@$session)) {
        $self->set_option(cur_user => $self->users->get_by_login($session->[0]));
        $self->response->add_cookie(qs => $session, expires => '+30d');
    }

    $self->set_app_locale('en');
    POSIX::setlocale(POSIX::LC_TIME, $ENV{'LC_ALL'});

    my @menu;

    push(@menu, {label => gettext('Packages'), path => 'package'});

    my @rbac_submenu;
    push(@rbac_submenu, {label => gettext('Roles'), cmd => 'roles'}) if $self->check_rights('rbac_roles_view');
    push(@rbac_submenu, {label => gettext('Roles rights'), cmd => 'role_rights'})
      if $self->check_rights('rbac_assign_rigth_to_role');
    push(@menu, {label => gettext('RBAC'), path => 'rbac', submenu => \@rbac_submenu}) if @rbac_submenu;

    my @user_submenu;
    push(@user_submenu, {label => gettext('Profile'), cmd => 'profile'}) if $self->get_option('cur_user');
    push(@user_submenu, {label => gettext('GPG keys'), cmd => 'gpg_keys'})
      if $self->check_rights('gpg_manage_public_keys');
    push(@menu, {label => gettext('Settings'), path => 'user', submenu => \@user_submenu}) if @user_submenu;

    $self->set_option(menu => \@menu);
}

sub process_timelog {
    my ($self, $tl) = @_;

    if ($self->get_option('show_timelog')) {
        if ($self->response && $self->response->content_type =~ /text\/html/ && defined($self->response->{'data'})) {
            my $tl_html = _tl2html($tl->_calc_percent([$tl->_analyze()]));
            (
                ref($self->response->{'data'}) eq 'SCALAR'
                ? ${$self->response->{'data'}}
                : $self->response->{'data'}
            ) =~ s/\<\/body\>/$tl_html<\/body>/;
        }
    }
}

sub process_mem_cycles {
    my ($self, @data) = @_;

    my $text = $self->SUPER::process_mem_cycles(@data);

    if ($self->response->content_type =~ /text\/html/ && $text) {
        my $html = $text;
        for ($html) {
            s/ /&nbsp;/g;
            s/\r|\n|\r\n/<br>/g;
        }
        $html = "<div style=\"background-color: #ffcccc; padding: 10px;\"><code>$html</code></div>";
        (
            ref($self->response->{'data'}) eq 'SCALAR'
            ? ${$self->response->{'data'}}
            : $self->response->{'data'}
        ) =~ s/(<body.*?>)/$1$html/;
    }

    return $text;
}

sub _tl2html {
    my ($log, $level) = @_;

    $level ||= 0;

    my $display = !$level ? 'block' : 'none';
    my $res = "<div style=\"padding-left: 20pt; display: $display;\">";

    foreach my $l (@$log) {
        my $text = html_encode($l->[0]);
        for ($text) {
            s/ /&nbsp;/g;
            s/\r|\n|\r\n/<br>/g;
        }
        my $time = sprintf('%f',   $l->[1]{'t'});
        my $prc  = sprintf('%.2f', $l->[1]{'prc'});

        $res .= '<table style="background-color: #eeeeee; width: 100%;"'
          . ' onmouseover="this.parentNode.style.backgroundColor=\'#cccccc\'" onmouseout="this.parentNode.style.backgroundColor=\'\'"><tr';
        $res .=
            ' style="cursor: pointer;"'
          . ' onclick="var tbl = this.parentNode; while (tbl.nodeName != \'TABLE\') { tbl = tbl.parentNode};'
          . 'var chld_div = tbl.nextSibling;'
          . 'if (this.firstChild.innerHTML == \'+\') {chld_div.style.display = \'block\'; this.firstChild.innerHTML = \'-\';} else {chld_div.style.display = \'none\'; this.firstChild.innerHTML = \'+\';};'
          . 'return false;"'
          if exists($l->[2]);
        $res .=
            '><th width="15pt" valign="top">'
          . (exists($l->[2]) ? '+' : '&nbsp;') . '</th>'
          . "<th valign=\"top\" width=\"100pt\">$time sec:</th><td valign=\"top\""
          . (
            $level
            ? "style=\"background-image: url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAUAAAAFCAIAAAACDbGyAAAAAXNSR0IArs4c6QAAABRJREFUCNdjfH1oPQMSYGJABaTyAbokAmZIPrAXAAAAAElFTkSuQmCC); background-size: $prc% 100%; background-repeat: no-repeat;\""
            : ''
          ) . ">$text</td></tr></table>";
        $res .= _tl2html($l->[2], $level + 1) if exists($l->[2]);
    }
    $res .= '</div>';

    return $res;
}

TRUE;
