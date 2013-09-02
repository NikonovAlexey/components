package User;
use Dancer ':syntax';

use Dancer::Session::Memcached;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::FAW;
use Dancer::Plugin::uRBAC;
use Dancer::Plugin::FlashNote;

use Digest::MD5 qw(md5_hex);
use Try::Tiny;

our $VERSION = '0.08';

prefix '/';

sub halt_session {
    session user => {
        id      => "",
        login => "",
        roles => "guest",
        email => "",
        fullname => "guest",
    };
};

fawform '/user/login' => {
    template    => 'components/renderform',
    redirect    => '/',

    formname    => 'loginform',
    title       => 'Вход в систему',
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
    before       => sub { if ($_[0] eq "post") {
        my $uname   = params->{username};
        my $upass   = params->{password};
        my $salt    = config->{salt} || "";
        my $user;
        # выкинуть нафиг все не-латинские символы
        $upass =~ /([A-Za-z0-9]*)/; $upass = $1 || "";
        $upass = md5_hex(md5_hex($upass) . $salt);
        
        try {
            $user = schema->resultset('User')->single({ 
                login    => $uname, 
                password => $upass,
            }) || 0;

            warning " ============ try to compare " . $user->login . " == $uname ";
        } catch {
            warning " ========= problems while find a user $uname:$upass";
            flash "Такой пользователь не найден, либо пароль был указан
            некорректно";
            halt_session();
            return(1, '/user/login');
        };
        
        if (( $user != 0 ) && ( $user->id > 0 ) ){
            session user => {
                id    => $user->id,
                login => $user->login,
                roles => $user->role,
                email => $user->email,
                fullname => $user->fullname,
                };
            session lifetime => time + config->{session_timeout};
            session longsession => 0;
            return(1, '/');
        } else {
            warning " ========= problems while find a user $uname:$upass";
            flash "Ваш логин в системе не обнаружен.";
        };
        halt_session();
        return(1, '/user/login');
    } },
};

any '/user/logout' => sub {
    halt_session();
    redirect '/';
};

any '/user/list' => sub {
    my $ulist = schema->resultset('User')->search({ 
        id => { '>' => 0 }
    }, {
        order_by => { -desc => 'id' }
    });

    template 'components/userlist' => {
        userslist => $ulist
    };
};

any '/user/add' => sub {
    my $ulist = schema->resultset('User')->create({
        login   => 'new',
        role    => 'user',
    });

    redirect '/';
};

fawform '/user/:id/edit' => {
    template    => 'components/renderform',
    redirect    => '/user/list',
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
            $user->update({
                login   => params->{login},
                role    => params->{role},
                email   => params->{email},
                fullname=> params->{fullname}
            });
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
