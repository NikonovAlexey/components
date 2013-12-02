package Menu;

use Dancer ':syntax';

use Dancer::Plugin::DBIC;
use Dancer::Plugin::FAW;
use Dancer::Plugin::uRBAC;
use Dancer::Plugin::Common;

use Try::Tiny;
use Data::Dump qw(dump);
use FindBin qw($Bin); 

our $VERSION = '0.08';

prefix '/';

=head MENU

Субмодуль, определяющий логику работы с пунктами меню.

=cut


=head1 Вспомогательные процедуры

Ряд процедур являются общими для этого модуля (например, как процедура
раскрытия списка ролей согласно правилам).

Другие процедуры расширяют логику шаблона дополнительными командами. Эти
процедуры отрисовывают пункты меню в зависимости от условий.

=cut

=head2 roles_unwrap

Берёт текущую роль пользователя из его сессии. Если роль не задана явно, то
роль считается гостевой.

Административная роль разворачивается в несколько более примитивных ролей.

Список ролей возвращается на выходе в виде одномерного массива.

=cut

sub roles_unwrap {
    my @roles = qw/%any%/;
    my $role = session->{user}->{roles} || "guest";
    $role = "%$role%";
    push(@roles, $role);
    if ( $role eq "admin" ) { push(@roles, "guest", "user", "manager") }

    return @roles;
}

=head2 z_unwrap

Служит одной единственной цели: разворачивает значения из БД в анонимный хэш, 
который и возвращает на выходе в виде результата.

=cut

sub z_unwrap {
    return {
        id  => $_[0]->id,
        name => $_[0]->name,
        url => $_[0]->url,
        weight => $_[0]->weight,
        type => $_[0]->type,
        alias => $_[0]->alias,
        note => $_[0]->note 
    }
}

=head2 h_stickin

Выполнить обход массива с поиском элемента с указанным id и вернуть указатель
на эту точку для дальнейшей с ней работы (например, вклеивания нового
элемента). 

=cut

sub h_stickin {
    my ( $hash, $id ) = @_;
    my $z;
    
    if ( $id eq "" ) { return undef };
    
    # пропустить все не-хэши
    if ( ref($hash) ne "HASH" ) { return "" }
    
    foreach my $key ( keys( %{$hash} ) ) {
        # пропустить все не-хэши
        next if ( ref($hash->{$key}) ne "HASH" );
        
        # вернуть указатель на хэш, если id совпадают 
        if ( $key eq $id ) { return($hash->{$key}) };
        
        #warning " ::::::::::::::::::: $key key " . dump(ref($hash->{$key}));
        $z = h_stickin($hash->{$key}, $id);
                     
        # обеспечить возврат значения на всю глубину рекурсии
        return $z if ( $z ne "" );
    }
}

=head2 h_root

Рекурсивно обойти весь хэш и вернуть ссылку на элемент, который является
заданным на входе корнем меню (по алиасу);

=cut

sub h_root {
    my ( $hash, $alias ) = @_;
    my $z;
    my $h_al;

    if ( $alias eq "" ) { return undef };
   
    # пропустить все не-хэши
    if ( ref($hash) ne "HASH" ) { return "" }
    
    foreach my $key ( keys( %{$hash} ) ) {
        # пропустить все не-хэши
        next if ( ref($hash->{$key}) ne "HASH" );
        
        # вернуть указатель на хэш, если id совпадают 
        $h_al = $hash->{$key}->{alias};
        if ( defined($h_al) && ( $h_al eq $alias ) ) { return($hash->{$key}) };

        $z = h_root($hash->{$key}, $alias);
        
        # обеспечить возврат значения на всю глубину рекурсии
        return $z if ( $z ne "" );
    }
}

=head2 menu

Вывод пунктов меню, подчинённых заданному на входе псевдониму.
Уровень подчинённости = дети первого уровня вложенности.

На входе указывать псевдоним меню.

Собирается список ролей, для которых будут отображаться пункты меню. Текущая
роль считается гостевой, если не указана явно. К ней добавляется роль "все =
any". Роль администратора разворачивается в список всех ролей: гость,
пользователь и менеджер.

Сложным запросом через JOIN выбираются все дочерние этому псевдониму элементы
меню с учётом списка ролей.

Результат запроса передаётся в сопоставленный шаблон.

Шаблон отрисовываться не будет, если есть ошибки в запросе или ошибки 
в шаблоне (например, система не может найти его по указанному пути).

=cut

sub menu {
    my ( $s, $engine, $out );
    
    ( $s ) = @_; $s ||= ""; 
    return "" if ($s eq "");
    
    my @roles = roles_unwrap();
    my $items;
    
    try {
        $items = schema->resultset('Menu')->search({ 
                'menus.roles' => { like => [ @roles ] },
                'me.alias'    => { like => "$s" },
            }, {
                join     => 'menus',
                'select' => ['menus.id', 'menus.name', 'menus.url',
                        'menus.alias', 'menus.type', 'menus.note'],
                'as'     => ['id', 'name', 'url', 'alias', 'type', 'note'],
                order_by => { -asc => 'menus.weight' },
            });
    } catch {
        warning " ========== oooops! wrong menu items";
    };
    
    return template_process('menu.tt', { 
                s => $s,
                menu => $items, 
                rights => \&rights
            });
}

=head2 menu_struct

Читает структуру меню из БД в многоуровневый хэш.

Каждый элемент меню считывается в хэш menuitem.

Допущение: считывание происходит в порядке хронологического создания элементов.
Перекрёстные ссылки (закольцовывание) не допускаются, однако не будут
циклически разрешаться (каждый элемент обрабатывается только один раз).

=cut

sub menu_struct {
    my ( $s, $engine, $out );
    my $el;
    
    ( $s ) = @_; $s ||= "";
    my ( $id, $parent );
    my $menu_struct;# = Data::SimplePath->new();
    
    my @roles = roles_unwrap();
    
    my $items = schema->resultset('Menu')->search({
        roles => { like => [ @roles ] },
    });
    if ( $items->count == 0 ) { return "" };
    # дальше - только если есть хоть что-то. Иначе - смысл???
    
    while( my $z = $items->next() ) {
        $id = $z->id; 
        # если родителя нет - элемент корневой и сам 
        # является для других родителем
        try { $parent = $z->parent->id } catch { $parent = "" };
        #$menu_struct->set("$parent", z_unwrap($z));
        
        if ( $parent ne "" ) {
            # вклеить элемент в нужную часть дерева
            $el = h_stickin($menu_struct, $parent);
            $el->{array}->{$id} = z_unwrap($z);
        } else {
            $menu_struct->{$id} = z_unwrap($z);
        }

    }
    
    return template_process("menu_struct_$s.tt", {
            s => $s,
            menu => h_root($menu_struct, $s)->{array},
            rights => \&rights
        });
}

=head2 menu_position 

Разворачивает вложенные пункты меню в плоское дерево для возможности быстрого
возврата на нужный уровень.

=cut

sub menu_position {
    my ( $s, $recursion_level, $engine );
    my ( $parent, $parentid ) = ( undef, 0 );
    my ( $out, $out2 ) = ( "", "" );
    my $current;
    
    # ничего не выводим, если алиас пустой
    ( $s, $recursion_level ) = @_; $s ||= ""; return "" if ($s eq "");
    $recursion_level ||= 0;
    
    # текущий элемент по его алиасу
    try {
        $current    = schema->resultset('Menu')->find({ alias => $s });
    } catch {
        $current    = undef;
    };
    try { 
        $parentid   = $current->parent->id;
    } catch {
        $parentid   = 0;
    };
    
    # алиас элемента-родителя 
    # если больше нуля, то можно спрашивать про алиас и отрисовывать родителя 
    if ( $parentid != 0 ) {
        $parent     = schema->resultset('Menu')->find({ id => $parentid });
        $out2       = menu_position($parent->alias, $recursion_level+1);

        if ($current->name ne "") {
            $out = template_process('menu_position.tt', { 
                s => $s,
                recursion_level => $recursion_level,
                currentmenu => $current 
                });
        } else {
            $out = "";
        }
    }
    
    return $out2 . $out;
}


=head1 Основные точки взаимодействия

Ниже перечислены процедуры, выполняющие основные взаимодействия с пунктами
меню: построение карты сайта, вывод всех пунктов меню списком, добавление,
удаление и правка пункта меню по его ID.

=cut

=head2 sitemap

Отобразить карту меню. Карта меню строится вниз от коренного псевдонима basic-left.

При построении карты меню учитывается текущая роль пользователя. Пункты меню не
попадут в список, если роли не будут совпадать.

=cut

any '/menu/sitemap' => sub {
    my $role = session->{user}->{roles} || "guest";
    $role = "%$role%";
    my @roles = ( "%any%", $role );
    
    template 'components/sitemap', {
        role => { like => [ @roles ] },
        top  => schema->resultset('Menu')->find({ 
            alias => 'basic-left'
        })
    };
};

=head2 listall

Вывести все пункты меню, отсортировав их по весу.

=cut

any '/menu/listall' => sub {
    template 'components/menu_listall', {
    top => schema->resultset('Menu')->search({}, {
        order_by => 'weight'
    })
    };
};

=head2 :id/add

Создаёт пункт меню с указанным на входе родителем. Родитель указывается по
псевдониму, а не по ID, как может показаться на первый взгляд.

Если родитель с алиасом :id не был найден, то будет создан корневой пункт
меню и к нему подвязан новый (текущий) пункт меню.

После создания нового пункта меню процедура перекинет шаблон к точке
редактирования, чтобы сразу можно было поправить все настройки.

=cut

any '/menu/:id/add' => sub {
    my ($parent, $item);
    
    if ( rights('admin') ) { 
        try {
            $parent = schema->resultset('Menu')->find({ alias => params->{id} })->id;
        } catch {
            $parent = schema->resultset('Menu')->create({ 
                parent  => undef,
                name    => params->{id},
                alias   => params->{id},
                url     => params->{id},
                weight  => 100,
                type    => '',
            })->id;
        };
        
        $item   = schema->resultset('Menu')->create({
            parent  => $parent || undef,
            name    => 'new menu item',
            url     => 'new-menu-item',
            weight  => '100',
            type    => undef,
            alias   => undef,
        });
        redirect "/menu/".$item->id."/edit";
    } else {
        redirect "/" 
    };
};

=head2 :id/delete

Удаление будет произведено только если у пользователя присутствуют права
администратора.

Попытка удаления перенаправляет на главную страницу.

Если удаление было выполнено успешно, произойдёт переход к списку пунктов меню.

=cut

any '/menu/:id/delete' => sub {
    my $item   = schema->resultset('Menu')->find({ id => params->{id} }) || undef;
    
    if ( rights('admin') ) { 
        if (defined($item)) { $item->delete; };
        redirect "/menu/listall";
        return 
    };
    
    redirect "";
};

=head2 :id/edit

Изменить пункт меню, определив его по ID

Происходит изменение пункта меню, основанное на его уникальном ID.

Отмена возвращает к списку меню. Подтверждение - переводит к страничке по url,
указанному в качестве параметра меню.

=cut

fawform '/menu/:id/edit' => {
    template    => 'components/renderform',
    redirect    => '/',
    formname    => 'menu-edit',
    title       => 'Изменить пункт меню',
    fields      => [
    {
        type    => 'text',
        name    => 'id',
        label   => 'идентификатор',
        note    => 'уникальный номер записи меню в таблицах'
    },
    {
        type    => 'text',
        name    => 'parent',
        label   => 'родитель',
        note    => 'меню-родитель'
    },
    {
        type    => 'text',
        name    => 'name',
        label   => 'название меню',
    },
    {
        type    => 'text',
        name    => 'url',
        label   => 'ссылка меню',
        note    => 'к странице по щелчку на меню'
    },
    {
        type    => 'text',
        name    => 'weight',
        label   => 'вес меню',
        note    => 'вес (число) относительно другого пункта меню'
    },
    {
        type    => 'text',
        name    => 'type',
        label   => 'тип меню',
    },
    {
        type    => 'text',
        name    => 'alias',
        label   => 'псевдоним',
        note    => 'выступает в роли пути меню'
    },
    {
        type    => 'text',
        name    => 'roles',
        label   => 'права',
        note    => 'группы пользователей, которые увидят этот пункт меню',
        value   => 'any',
    },
    {
        type    => 'text',
        name    => 'note',
        label   => 'подпись',
        note    => 'подпись к пункту меню',
        value   => '',
    },
    ],
    buttons     => [
        {
            name        => 'submit',
            value       => 'Применить'
        },
        {
            name        => 'submit',
            value       => 'Отменить'
        },
    ],
    before      => sub {
        my $faw  = ${$_[1]};
        my $id   = params->{id};
        my $path = $faw->fieldset(":id" => $id);
        my $menu = schema->resultset('Menu')->find({ id => $id });
        
        if ( ($_[0] eq "get") && defined($menu) ) { 
            $faw->map_params_by_names($menu, qw(
                id parent name url weight type alias roles note
        )); };
        
        if ($_[0] eq "post") {
            return (1, "/menu/listall") if (params->{submit} eq "Отменить");
            $menu->update({
                parent  => params->{parent},
                name    => params->{name},
                url     => params->{url},
                weight  => params->{weight},
                type    => params->{type},
                alias   => params->{alias},
                roles   => params->{roles},
                note    => params->{note},
            });
            my $url = params->{url};
            if (!( defined($url) && ( $url ne "" ) )) { $url = "/menu/listall"; }
            return (1, $url);
        };
    },
};

=head2 before_template_render

Внедрение процедур для использования в шаблонах.

=cut

hook before_template_render => sub {
    my ( $tokens ) = @_;
    $tokens->{menu} = \&menu;
    $tokens->{menu_position} = \&menu_position;
    $tokens->{menu_struct} = \&menu_struct;
};

=head2 init

Процедура инициации таблицы.

=cut

our $createsql = qq|
CREATE TABLE menu (
    id     int(10) NOT NULL AUTO_INCREMENT, 
    parent int(10), 
    name   varchar(255) NOT NULL, 
    url    varchar(255) NOT NULL, 
    weight int(100) NOT NULL, 
    type   varchar(32), 
    alias  varchar(255), 
    roles  varchar(64),
    note   varchar(255),
    PRIMARY KEY (id)
) CHARACTER SET = utf8;

ALTER TABLE menu 
    ADD INDEX parent (parent),
    ADD CONSTRAINT parent FOREIGN KEY (parent) REFERENCES menu (id);
|;

true;
