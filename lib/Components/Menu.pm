package Menu;

use Dancer ':syntax';

use Dancer::Plugin::DBIC;
use Dancer::Plugin::FAW;
use Dancer::Plugin::uRBAC;

use Data::Dump qw(dump);
use FindBin qw($Bin); 

our $VERSION = '0.05';

prefix '/menu';
# TODO: при изменении пути модуля проверить все редиректы внутри модуля.

any '/sitemap' => sub {
    template 'components/sitemap', {
        top => schema->resultset('Menu')->find({ 
            alias => 'left'
        }, {
            order_by => 'weight'
        })
    };
};

fawform '/:id/edit' => {
    template    => 'components/renderform',
    redirect    => '/',

    formname    => 'menu-edit',
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
                id parent name url weight type alias
        )); };
        
        if ($_[0] eq "post") {
            return (1, params->{url}) if (params->{submit} eq "Отменить");
            $menu->update({
                parent  => params->{parent},
                name    => params->{name},
                url     => params->{url},
                weight  => params->{weight},
                type    => params->{type},
                alias   => params->{alias}
            });
            return (1, params->{url});
        };
    },
};

any '/:id/add' => sub {
    my ($parent, $item);

    if ( rights('admin') ) { 
        $parent = schema->resultset('Menu')->find({ alias => params->{id} })->id;
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

any '/:id/delete' => sub {
    my $item   = schema->resultset('Menu')->find({ id => params->{id} }) || undef;
    my $parent = "/page/" . $item->alias || "";
    if ( rights('admin') ) { 
        if (defined($item)) { $item->delete; };
    };
    redirect $parent;
};

# Подготовка общей инфы для всех страничек
hook before_template_render => sub {
    my ( $tokens ) = @_;
    $tokens->{menu} = \&menu;
    $tokens->{menu_position} = \&menu_position;
};

sub menu {
    my ( $s, $engine, $out );

    ( $s ) = @_; $s ||= ""; return "" if ($s eq "");
    
    my $parentid    = schema->resultset('Menu')->find({ alias => $s });
    $parentid       = (defined($parentid)) ? $parentid->id : 0;
    if ($parentid > 0) {
        my $items = schema->resultset('Menu')->search({ 
                parent => $parentid 
            }, {
                order_by => { -asc => 'weight' },
            });
        $engine = Template->new({ INCLUDE_PATH => $Bin . '/../views/' });
        $engine->process('components/menu.tt', { s => $s, menu => $items, rights => \&rights }, \$out);
    } else {
        $out = "";
    }

    return $out;
};

sub menu_position {
    my ( $s, $recursion_level, $engine );
    my ( $parent, $parentid );
    my ( $out, $out2 ) = ( "", "" );

    # ничего не выводим, если алиас пустой
    ( $s, $recursion_level ) = @_; $s ||= ""; return "" if ($s eq "");
    $recursion_level ||= 0;
    
    # текущий элемент по его алиасу
    my $current     = schema->resultset('Menu')->find({ alias => $s }) || undef;
    
    # алиас элемента-родителя 
    # если больше нуля, то можно спрашивать про алиас и отрисовывать родителя 
    if (defined($current) && defined($current->parent) && defined($current->parent->id)) {
        $parentid   = $current->parent->id || 0;
        $parent     = schema->resultset('Menu')->find({ id => $parentid });
        $out2       = menu_position($parent->alias, $recursion_level+1);

        if ($current->name ne "") {
            $engine = Template->new({ INCLUDE_PATH => $Bin . '/../views/' });
            $engine->process('components/menu_position.tt', { 
                s => $s,
                recursion_level => $recursion_level,
                currentmenu => $current },
                \$out);
        } else {
            $out = "";
        }
    }

    return $out2 . $out;
};

our $createsql = qq|
CREATE TABLE menu (
    id     int(10) NOT NULL AUTO_INCREMENT, 
    parent int(10), 
    name   varchar(255) NOT NULL, 
    url    varchar(255) NOT NULL, 
    weight int(100) NOT NULL, 
    type   varchar(32), 
    alias  varchar(255), 
    PRIMARY KEY (id)
) CHARACTER SET = utf8;

ALTER TABLE menu 
    ADD INDEX parent (parent),
    ADD CONSTRAINT parent FOREIGN KEY (parent) REFERENCES menu (id);
|;

true;
