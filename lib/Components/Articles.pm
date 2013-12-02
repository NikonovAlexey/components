package Articles;

use utf8;
use Dancer ':syntax';

use Dancer::Plugin::DBIC;
use Dancer::Plugin::FAW;
use Dancer::Plugin::uRBAC;
use Dancer::Plugin::ImageWork;
use Dancer::Plugin::Common;

use Image::Magick;
use Digest::MD5 qw(md5_hex);
use Data::Dump qw(dump);
use FindBin qw($Bin);
use Encode;

use Archive::Zip;
use XML::LibXML::Reader;
use Try::Tiny;

our $VERSION = '0.08';

prefix '/';

=head ARTICLES

=cut

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

post '/page/create' => sub {
    my $pagename    = params->{pagename} || "";
    my $translname;
    
    $pagename =~ s/  / /g;
    $pagename =~ s/^ *//g;
    $pagename =~ s/ *$//g;
    
    redirect "/page/listall" if ($pagename eq "");
    $translname  = transliterate($pagename) || "";
    
    try {
        schema->resultset('Article')->create({ 
            title   => $pagename,
            url     => $translname,
            author  => session->{user}->{fullname},
        });
    } catch {
        warning " article with $pagename already defined ";
    };
    redirect "/page/$translname/edit";
};

any '/page/:tag/add' => sub {
    my $pagename    = params->{tag} || "";
    my $translname;
    
    $pagename =~ s/  / /g;
    $pagename =~ s/^ *//g;
    $pagename =~ s/ *$//g;
    
    redirect "/page/listall" if ($pagename eq "");
    $translname  = transliterate($pagename) || "";
    
    try {
        schema->resultset('Article')->create({ 
            title   => $pagename,
            url     => $translname,
            author  => session->{user}->{fullname},
        });
    } catch {
        warning " article with $pagename already defined ";
    };
    redirect "/page/$translname/edit";
};

=head2 delete :id page

=cut

any '/page/:pageid/delete' => sub {
    my $pageid = params->{pageid} || 0;
    
    try {
        my $page = schema->resultset('Article')->find({
            id      => $pageid
        });
        $page->delete;
    } catch {
        warning " ========= try to delete # $pageid page ";
    };
    redirect "/page/listall";
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

sub importimage {
    my ( $zip, $name, $type, $gal ) = @_;
    
    my $cnt = schema->resultset('Image')->search({
        imagename   => $name,
    });
    
    if ( $cnt->count > 0 ) {
        $cnt = schema->resultset('Image')->search({
            imagename   => $name,
        });
        return($cnt->first->filename, $cnt->first->id);
    }
    
    my $galtype  = $type || "common";
    my $filename = $name;
    my ( $path, $file, $ext ) = img_fileparse( $filename );
    my $tempname = "/tmp/" . md5_hex(encode_utf8(localtime . $filename)) . ".$ext";
    $zip->extractMemberWithoutPaths( $name, $tempname );
    ( $path, $file, $ext ) = img_resize_by_rules( $tempname, $gal );

    my $id = schema->resultset('Image')->create({
        filename    => img_relative_folder($gal) . "$file.$ext",
        imagename   => $filename,
        remark      => '',
        type        => $galtype,
        alias       => $gal,
    });

    return ("$path$file.$ext", $id->id);
}

fawform '/page/:url/attach' => {
    template    => 'components/renderform',
    redirect    => '/page/:url',
    formname    => 'editpage',
    title       => 'Добавить текст',

    fields      => [
    {
        type    => 'upload',
        name    => 'document',
        label   => 'документ *.odt',
        note    => 'укажите документ в формате OpenOffice/LibreOffice для загрузки вместе с рисунками.',
        default => '',
    },
    {
        type    => 'text',
        name    => 'type',
        label   => 'тип фотографии',
        note    => 'к какому типу изображений будут относиться картинки (доп.
        свойство для фильтрации и преобразований)',
        default => '',
    },
    {
        type    => 'text',
        name    => 'alias',
        label   => 'галерея',
        note    => 'как будет называться галерея (псевдоним раздела), в который
        должны быть помещены картинки',
        default => '',
    }
    ],
    
    buttons  => [
        { name    => 'submit', value   => 'Применить', classes => [ 'btn', 'btn-success' ], },
        { name    => 'submit', value   => 'Отменить', classes => ['btn'], },
    ],
    
    before => sub {
        my $faw = ${ $_[1] };
        my $path = params->{url};
        my $text = schema->resultset('Article')->single({ url => $path });
        
        if ( $_[0] eq "get" ) { 
            $faw->empty_form(); 
            $faw->map_params(
                type        => "pagesphoto",
                alias       => $path,
            );
            $faw->{action} = request->path;
        }
        
        if ( $_[0] eq "post" ) {
            if ( params->{submit} eq "Отменить" ) { return ( 1, '/page/' . $path ) }
            if ( ! defined($text->id) ) {
                return (0, '');
            }
            
            my $imagesarch = request->{uploads}->{document} || "";
            return(0, '') if ($imagesarch->{tempname} eq "");
            
            my $zip = Archive::Zip->new($imagesarch->{tempname});
            my $tint = time();
            
            my $doc = $zip->contents("content.xml");
            my $xml = XML::LibXML::Reader->new(string => $doc);
            my $docpage = "";
            $xml->nextPatternMatch("//office:document-content/office:body");
            while( my $node = $xml->read() ) {
                # получим адрес изображения в файле, который нужно вставить в документ
                if ( $xml->name eq "draw:image" ) {
                    my ( $ref, $id ) = importimage($zip, $xml->getAttribute("xlink:href"), params->{type}, params->{alias} );
                    $docpage .= img_by_num_lb("imglb=", $id);
                }
                # получим текст из атрибута
                if ( $xml->hasValue() ) { 
                    $docpage .= "<p>" . $xml->value . "</p>";
                }
            }
            
            $docpage = $text->text . $docpage;
            $text->update({
                text        => $docpage,
                lastmod     => time,
            });
            
            return ( 1, '/page/' . $path );
        }
    },
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
    
    return template_process('news.tt', { 
            s => $s,
            articles => $items
        });
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
