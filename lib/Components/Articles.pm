package Articles;

use utf8;
use Dancer ':syntax';

use Dancer::Plugin::DBIC;
use Dancer::Plugin::FAW;
use Dancer::Plugin::uRBAC;

use Image::Magick;
use Digest::MD5 qw(md5_hex);
use Data::Dump qw(dump);
use FindBin qw($Bin);
use Encode;

use Try::Tiny;

our $VERSION = '0.05';

prefix '/';

=head ARTICLES

=cut

sub img_by_num {
    my ( $src, $id ) = @_;
    my $image;
    my $file = "";

    try {
        $image = schema->resultset('Image')->find({ id => $id }) || 0;
        $file = $image->filename || "";
    } catch {
        return "$src$id";
    };
    
    return "$src$id" if $file eq "";
    return "<img src='$file'>";
}

sub link_to_text {
    my ( $src, $link ) = @_;
    return "<a href='/page/$link'>$link</a>";
}

sub parsepage {
    my $text = $_[0];
    
    $text =~ s/(img\s*=\s*)(\d*)/&img_by_num($1,$2)/egm;
    $text =~ s/(link\s*=\s*)(\w*)/&link_to_text($1,$2)/egm;
    return $text;
}

any '/page/sitemap.xml' => sub {
    my $articles = schema->resultset('Article')->search({
    }, {
        order_by => 'id',
        columns  => 'url',
    });
    template 'components/sitemap_xml', {
        pages => $articles
    }, {
        layout => ""
    };
};

any '/page/news.xml' => sub {
    my $lastdate = config->{components}->{documents}->{newsfresh} || 10 * 86400;
    my $newsfresh = time - $lastdate;
    
    my $articles = schema->resultset('Article')->search({
        -or => [
            -and => [
                type    => 'news',
                lastmod => { '>=' => $newsfresh },
            ],
            type    => 'fix',
        ]
    }, {
        order_by => { -desc => 'lastmod' },
        columns  => [ qw/url title description lastmod/ ],
    });
    template 'components/newsfeed_xml', {
        now     => time,
        pages   => $articles
    }, {
        layout  => ""
    };
};

any '/page/listall' => sub {
    my $pages   = schema->resultset('Article')->search({},{
        order_by => 'id',
    });

    template 'components/page-listall', {
        pagelist    => $pages
    };
};

any '/page/:url' => sub {
    my $url     = param('url');
    my $text    = schema->resultset('Article')->single({ url => $url });
    
    if (defined($text)) {
        template 'page' => {
            title   => $text->title || $text->url,
            description => $text->description || "",
            text    => $text,
            url     => $url,
        };
    } else {
        template 'blocks/404' => { 
            url     => $url, 
            title   => 'нет странички',
        };
    };
};

# правка документа 
fawform '/page/:url/edit' => {
    template    => 'components/renderform',
    redirect    => '/page/:url',
    formname    => 'editpage',
    title       => 'Изменить страничку',
    fields      => [ 
        {
            required    => 1,
            type        => 'text',
            name        => 'title',
            label       => 'Заголовок статьи',
            note        => 'Укажите заголовок статьи',
            default     => '',
        },
        {
            required    => 1,
            type        => 'text',
            name        => 'url',
            label       => 'Адрес на сайте:',
            note        => 'Укажите здесь URL странички на сайте.',
            default     => '',
        },
        {
            type        => 'text',
            name        => 'description',
            label       => 'Краткое описание',
            default     => '',
        },
        {
            type        => 'text',
            name        => 'author',
            label       => 'Автор статьи',
            default     => '',
        },
        {
            type        => 'text',
            name        => 'type',
            label       => 'Тип материала',
            note        => 'Укажите тип материала "news", если это новость',
            default     => '',
        },
        {
            required    => 1,
            type        => 'wysiwyg',
            name        => 'content',
            label       => ' ',
            default     => '',
        },
    ],
    buttons     => [
        {
            name        => 'submit',
            value       => 'Применить'
        },
        {
            name        => 'reset',
            value       => 'Отменить',
            classes     => ['warn'],
        },
    ],
    before      => sub {
        # Очень интересный пример работы с вычисляемыми путями. Нам может
        # потребоваться передавать в пути изменяемые аргументы и менять
        # поведение формы в зависимости от этих аргументов.
        
        # Сначала мы прочтём $faw и текущий путь для редактирования
        my $faw  = ${$_[1]};
        my $path = params->{url};
        
        my $text = schema->resultset('Article')->single({ url => $path });
        
        # В случае, если это действие get, 
        if ($_[0] eq "get") {
            if (defined($text)) { 
                # то следует подставить значения по умолчанию из БД.
                $faw->map_params(
                    url         => $text->url, 
                    title       => $text->title,
                    content     => $text->text,
                    type        => $text->type,
                    description => $text->description,
                    author      => $text->author,
                );
            } else {
                # или же (когда такой записи ещё нет в БД) то просто установить
                # текущий путь, т.е. использовать вычисляемые значения по умолчанию.
                $faw->map_params(url => $path);
            }
            # и поместить ссылку на вычисляемый путь в эту форму.
            $faw->{action} = request->path;
        }
        
        if ($_[0] eq "post") {
            # выход по кнопке "отмена" = reset;
            return (1, "/page/$path") if defined(params->{'reset'});
            #
            try {
            $text->update({
                url         => params->{url},
                title       => params->{title} || "",
                description => params->{description} || "",
                author      => params->{author} || "",
                type        => params->{type} || "",
                text        => parsepage(params->{content}) || "",
                lastmod     => time,
            });
            } catch {
                return 0;
            };
            return (1, "/page/$path");
        }
    },
};

any '/page/:tag/add' => sub {
    my $tag = params->{tag};
    try {
        schema->resultset('Article')->create({ 
            url     => $tag,
            author  => session->{user}->{fullname},
        });
    } catch {
        warning " article with $tag already defined ";
    };
    redirect "/page/$tag/edit";
};

# Подготовка общей инфы для всех страничек
hook before_template_render => sub {
    my ( $tokens ) = @_;
    $tokens->{news} = \&news;
};

sub news {
    my ( $s, $engine, $out );
    
    my $lastdate = config->{components}->{documents}->{newsfresh} || 10 * 86400;
    my $newsfresh = time - $lastdate;
    
    warning " ================= $newsfresh : $lastdate ";
    
    my $items = schema->resultset('Article')->search({
        -or => [
            -and => [
                type    => 'news',
                lastmod => { '>=' => $newsfresh },
            ],
            type    => 'fix',
        ]
        }, {
            order_by => { -desc => 'id' },
            rows     => 5,
        });
    $engine = Template->new({
        INCLUDE_PATH => $Bin . '/../views/',
        ENCODING => 'utf8',
    });
    $engine->process('components/news.tt', 
        { s => $s, articles => $items }, 
        \$out, );
    return $out;
};

our $createsql = qq|
CREATE TABLE article (
    id          int(10) NOT NULL AUTO_INCREMENT, 
    description varchar(255), 
    url         varchar(255) NOT NULL UNIQUE, 
    text        text, 
    author      varchar(255) DEFAULT 'admin', 
    type        varchar(255), 
    title       varchar(255), 
    lastmod     int(11) DEFAULT 0,
    PRIMARY KEY (id)
) CHARACTER SET = utf8;
|;

true;
