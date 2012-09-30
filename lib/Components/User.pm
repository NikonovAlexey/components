package User;
use Dancer ':syntax';

use Dancer::Session::Memcached;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::FAW;
use Dancer::Plugin::uRBAC;

use Digest::MD5 qw(md5_hex);
use Try::Tiny;

our $VERSION = '0.05';

prefix '/user';

fawform '/login' => {
    template    => 'components/renderform',
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
        my $uname = params->{username};
        my $upass = params->{password};
        my $salt    = config->{salt} || "";
        # выкинуть нафиг все не-латинские символы
        $upass =~ /([A-Za-z0-9]*)/; $upass = $1 || "";
        $upass = md5_hex(md5_hex($upass) . $salt);
        my $user = schema->resultset('User')->find({
            login => $uname,
            password => $upass 
        });

        if ( (defined $user) && ( $user->id > 0 ) ) {
            session user => {
                login => $user->login,
                roles => $user->role,
                email => $user->email,
                fullname => $user->fullname,
                };
        } else {
            session user => {
                login => "",
                roles => "guest",
                email => "",
                fullname => "guest",
            };
        };
    } },
};

any '/logout' => sub {
    #session->destroy;
    session user => { roles => "guest" };
    redirect '/';
};

any '/list' => sub {
    my $ulist = schema->resultset('User')->search({ 
        id => { '>' => 0 }
    }, {
        order_by => { -desc => 'id' }
    });

    template 'components/userlist' => {
        userslist => $ulist
    };
};

any '/add' => sub {
    my $ulist = schema->resultset('User')->create({
        login   => 'new',
        role    => 'user',
    });

    redirect '/';
};

fawform '/:id/edit' => {
    template    => 'components/renderform',
    redirect    => prefix . '/list',

    formname    => 'edituser',
    fields      => [
        {
            type        => 'text',
            name        => 'login',
            label       => 'Логин',
            note        => 'Измените логин для входа в систему.',
        },
        {
            type        => 'text',
            name        => 'role',
            label       => 'Роль',
            note        => 'смените роль пользователя.',
        },
        {
            type        => 'text',
            name        => 'email',
            label       => 'E-mail',
            note        => 'задайте почтовый ящик пользователя.',
        },
        {
            type        => 'text',
            name        => 'fullname',
            label       => 'ФИО',
            note        => 'полное величание человека.',
        },
    ],
    buttons     => [
        {
            name        => 'submit',
            value       => 'изменить'
        },
        {
            name        => 'submit',
            value       => 'отменить'
        },
    ],
    before      => sub {
        my $faw  = ${$_[1]};
        my $id   = params->{id};
        my $path = $faw->fieldset(":id" => $id);
        
        my $user = schema->resultset('User')->find({ id => $id });
        
        if ($_[0] eq "get") {
            if (defined($user)) { 
                $faw->map_params_by_names(
                    $user, qw(login role email fullname));
            };
        };

        if ($_[0] eq "post") {
            # в случае ошибки в данных 0, в случае успеха = 1
            try {
                $user->update({
                    login   => params->{login},
                    role    => params->{role},
                    email   => params->{email},
                    fullname=> params->{fullname}
                });
            } catch {
                return 0;
            };
            return 1;
        };
    },
};

our $createsql = qq|
CREATE TABLE users (
    id       int(10) NOT NULL AUTO_INCREMENT, 
    login    varchar(32) NOT NULL UNIQUE, 
    password varchar(64) NOT NULL UNIQUE, 
    role     varchar(16) DEFAULT 'user' NOT NULL, 
    email    varchar(255), 
    fullname varchar(255), 
    PRIMARY KEY (id)
) CHARACTER SET = utf8;
|;

true;
