package Articles;

use Dancer ':syntax';

use Dancer::Plugin::DBIC;
use Dancer::Plugin::FAW;
use Dancer::Plugin::uRBAC;

use Image::Magick;
use Digest::MD5 qw(md5_hex);
use Data::Dump qw(dump);
use FindBin qw($Bin);

our $VERSION = '0.05';

prefix '/page';

post '/uploadimage' => sub {
    my $upload = request->{uploads}->{image};
    my $filename = $upload->{filename};
    my $filetemp = $upload->{tempname};
    my $filesize = $upload->{size};
    my ( $image, $x, $y, $k );

    $filename    =~ /\.(\w{3})/;
    my $fileext  = lc($1) || "png";

    my $destpath =  "/images/uploaded/";
    my $destfile = "" . md5_hex($filetemp . $filesize);
    my $abspath  = $Bin . "/../public" . $destpath;
    
    #move($filetemp, $abspath . $destfile);
    
    # прочтём рисунок и его параметры
    $image      = Image::Magick->new;
    $image->Read($filetemp);
    ( $x, $y )  = ($image->Get('width'), $image->Get('height'));

    # вычислим коэффициент уменьшения для полноразмерного эскиза
    $k          = ( $x / 1024 > $y / 768 ) ? $x / 1024 : $y / 768;
    $k          = ( $k < 1 ) ? 1 : $k;
    # масштабируем и запишем
    $image->Resize(geometry => $x/$k . 'x' . $y/$k );
    $image->Write($abspath . $destfile . ".$fileext");

    # то же - для превью (вставки в текст документа);
    $k          = ( $x / 320 > $y / 240 ) ? $x / 320 : $y / 240;
    $k          = ( $k < 1 ) ? 1 : $k;
    $image->Resize(geometry => $x/$k . 'x' . $y/$k );
    $image->Write($abspath . $destfile . "_sm.$fileext");
    
    schema->resultset('Image')->create({
        filename    => "${destpath}${destfile}.$fileext" || "",
        imagename   => request->{uploads}->{image}->{filename} || "",
        remark      => "",
        type        => "matherial",
        alias       => "matherial",
    });
    
    my $z = { upload => { image => { width => $x/$k }, links => { 
        original => $destpath . $destfile . "_sm.$fileext",
        lightboxed => $destpath . $destfile . ".$fileext", 
    } } };
    
    content_type 'application/json';
    return to_json($z);
};

any '/:url' => sub {
    my $url     = param('url');
    my $text    = schema->resultset('Article')->find({ url => "$url" });
    
    if (defined($text)) {
        template 'page' => {
            title   => $text->title || $text->url,
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
fawform '/*/edit' => {
    template    => 'components/renderform',
    redirect    => '/',
    layout      => 'edit',
    
    formname    => 'editpage',
    fields      => [ 
        {
            required    => 1,
            type        => 'text',
            name        => 'title',
            label       => 'Заголовок статьи',
            note        => 'Укажите заголовок статьи',
        },
        {
            required    => 1,
            type        => 'text',
            name        => 'url',
            label       => 'Адрес на сайте:',
            note        => 'Укажите здесь URL странички на сайте.',
        },
        {
            type        => 'text',
            name        => 'description',
            label       => 'Краткое описание',
        },
        {
            type        => 'text',
            name        => 'author',
            label       => 'Автор статьи',
        },
        {
            type        => 'text',
            name        => 'type',
            label       => 'Тип материала',
            note        => 'Укажите тип материала "news", если это новость',
        },
        {
            required    => 1,
            type        => 'wysiwyg',
            name        => 'content',
            label       => ' ',
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
        my $path = ''.params->{splat}[0];
        
        # В случае, если это действие get, 
        if ($_[0] eq "get") {
            my $text = schema->resultset('Article')->find({ url => $path });
            if (defined($text)) { 
                # то следует подставить значения по умолчанию из БД.
                $faw->map_params(
                    url         => $text->url, 
                    content     => $text->text,
                    type        => $text->type,
                    description => $text->description,
                    author      => $text->author,
                    title       => $text->title,
                );
            } else {
                # или же (когда такой записи ещё нет в БД) то просто установить
                # текущий путь, т.е. использовать вычисляемые значения по умолчанию.
                $faw->map_params(url => $path);
            }
            # и поместить ссылку на вычисляемый путь в эту форму.
            $faw->{action} = request->path;
        }
        # Кроме того, мы можем указать вычисляемый путь для перехода при записи/отмене
        $faw->{redirect} = "/page/$path";
    },
    after       => sub { if ($_[0] eq "post") {
        my $text   = schema->resultset('Article')->find({ 
            url  => params->{url},
        }) || undef;
        if (defined($text)) {
            $text->update({
                url         => params->{url},
                title       => params->{title} || "",
                description => params->{description} || "",
                author      => params->{author} || "",
                type        => params->{type} || "",
                text        => params->{content} || "",
            });
        } else {
            schema->resultset('Article')->create({
                url         => params->{url},
                title       => params->{title} || "",
                description => params->{description} || "",
                author      => params->{author} || "",
                type        => params->{type} || "",
                text        => params->{content} || "",
            });
        }
    } },
};


# Подготовка общей инфы для всех страничек
hook before_template_render => sub {
    my ( $tokens ) = @_;
    $tokens->{news} = \&news;
};

sub news {
    my ( $s, $engine, $out );

    my $items = schema->resultset('Article')->search({
            type     => "news",
        }, {
            order_by => { -desc => 'id' },
            rows     => 5,
        });
    $engine = Template->new({ INCLUDE_PATH => $Bin . '/../views/' });
    $engine->process('components/news.tt', { s => $s, articles => $items }, \$out);

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
    PRIMARY KEY (id)
) CHARACTER SET = utf8;
|;

true;
