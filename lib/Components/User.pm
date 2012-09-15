package User;
use Dancer ':syntax';

use Dancer::Session::Memcached;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::FAW;
use Dancer::Plugin::uRBAC;

use Digest::MD5 qw(md5_hex);

our $VERSION = '0.05';

prefix '/user';

fawform '/login' => {
    template    => 'login',
    redirect    => '/',

    formname    => 'loginform',
    fields      => [
        {
            type        => 'text',
            name        => 'username',
            label       => 'Логин',
            note        => 'Укажите логин для входа в систему.',
        },
        {
            type        => 'password',
            name        => 'password',
            label       => 'Пароль',
            note        => 'введите пароль для подтверждения полномочий.',
        },
    ],
    buttons     => [
        {
            name        => 'submit',
            value       => 'Войти'
        },
    ],
    after       => sub { if ($_[0] eq "post") {
        my $pass = params->{password};
        # выкинуть нафиг все не-латинские символы
        $pass =~ /([A-Za-z0-9]*)/; $pass = $1 || "";
        $pass = md5_hex(md5_hex($pass) . "MaNneopLAN");
        session user => { roles => "guest" };
        if ( $pass eq config->{admin_password} ) {
            session user => {roles => "admin"};
            #warning " =================================== ::::::::::::::::: change session status";
        };
    } },
};

any '/logout' => sub {
    #session->destroy;
    session user => { roles => "guest" };
    redirect '/';
};

true;
