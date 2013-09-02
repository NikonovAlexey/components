package Gallery;

use Dancer ':syntax';

use Dancer::Plugin::DBIC;
use Dancer::Plugin::FAW;
use Dancer::Plugin::uRBAC;
use Dancer::Plugin::ImageWork;

use Image::Magick;
use Digest::MD5 qw(md5_hex);
use FindBin qw($Bin);
use Try::Tiny;
use Data::Dump qw(dump);
use Encode qw(encode_utf8);
use File::Glob ':glob';
use File::Copy qw(copy);

use Archive::Zip;

our $VERSION = '0.08';

prefix '/';

=head GALLERY

Взаимодействия с галереями изображений и с картинками.

=cut

=head1 Вспомогательные процедуры

=cut

=head2 gallery

Мы можем захотеть встраивать в нашу страничку определённую галерею. Это
делается с помощью команды gallery, которая доступна в шаблоне. За вывод в
шаблон самих рисунков из галереи отвечает этот код.

=cut

sub gallery {
    my ( $s, $t, $engine, $out );
    my $items;
    my $path;
    
    ( $s, $t ) = @_; $s ||= ""; 
    
    $path = request->{path}; $path =~ s/\/+/-/g; $path =~ s/^-//;
    if ( -e $Bin . "/../public/images/" . $path . ".jpg" ) {
        $path = "/images/$path.jpg";
    } else {
        $path = config->{components}->{gallery}->{topbanner} || "top-banner";
        $path = "/images/" . $path . ".jpg";
    };
    
    # это не меню - даже если мы ничего не получили на входе, 
    # надо вывести хотя бы одну заглушку-изображение. А это поведение
    # определяется в шаблоне
    $t ||= "top-banner";
    
    if ($s ne "") {
        $items = schema->resultset('Image')->search({ 
            alias => $s,
            type => $t
        }, {
            order_by => { -asc => 'id' },
        });
        try { if ( $items->count() < 1 ) {
            $items = schema->resultset('Image')->search({
                type => $t
            }, {
                rows => 5,
                order_by => 'RAND()',
            });
        } catch { $items = schema->resultset('Image')->search({
                type => $t
            }, {
                rows => 5,
                order_by => 'RAND()',
            });
        };
    };
    }
    
    return template_process('gallery.tt', {
        s       => $s,
        gallery => $items,
        path    => $path,
        rights  => \&rights 
    });
}


=head1 Основные точки взаимодействия

=cut

=head2 *

Закольцовывает страничку на дефолтный шаблон, чтобы не возникало ошибок при
некорректном доступе.

=cut

any '/gallery/' => sub { redirect '/gallery/list'; };

=head2 list

Выводит перечень галерей изображений.

=cut

any '/gallery/list' => sub {
    my $gallist = schema->resultset('Image')->search(undef, {
        select => [ 'alias', 'type' ],
        distinct => 1,
        order_by => { -asc => [qw/type alias/] },
        group_by => [qw/type alias/],
    });

    template 'components/gallist' => {
        gallist => $gallist,
    };
};

=head2 top-banner-all

Создаёт список всех изображений, содержащих в своём типе "top-banner".
Была создана для проекта man-kmv.

=cut

any '/gallery/top-banner-all' => sub {
    my $images  = schema->resultset('Image')->search({
        type    => { like => '%top-banner%' },
    }, {
        order_by => 'id',
    });

    template 'gallery', {
        list    => $images
    };
};

=head2 multiload

Подать много рисунков в одном архиве, чтобы добавить их все разом.

=cut

fawform '/gallery/multiload' => {
    template    => 'components/renderform',
    redirect    => '/',
    formname    => 'gallery-multiload',
    title       => 'Изменить рисунок в галерее',
    fields      => [
    {
        type    => 'upload',
        name    => 'imagesarch',
        label   => 'архив рисунков',
        note    => 'укажите архив с рисунками, из которых будет создана новая галерея',
        default => '',
    },
    {
        type    => 'text',
        name    => 'type',
        label   => 'тип фотографии',
        note    => 'к какому типу изображений относится данная картинка (доп.
        свойство для фильтрации и преобразований)',
        default => '',
    },
    {
        type    => 'text',
        name    => 'alias',
        label   => 'галерея',
        note    => 'как будет называться галерея (псевдоним раздела)',
        default => '',
    }
    ],
    buttons     => [
        { name        => 'submit', value       => 'Применить' },
        { name        => 'submit', value       => 'Отменить' },
    ],
    before      => sub {
        my $faw  = ${$_[1]};
        my $alias   = params->{alias};
        my $type    = params->{type} || "pagesphoto";
        my $gallery = params->{gallery} || "";
        
        if ($_[0] eq "get") {
            $faw->map_params(
                type        => $type,
                alias       => $gallery,
            );
        };
        
        if ($_[0] eq "post") {
            return(1, "/gallery/" . params->{alias} ) if (params->{submit} eq "Отменить");
            my $imagesarch = request->{uploads}->{imagesarch} || "";
            my $gallery = params->{alias};
            if (defined( $imagesarch ) && ($imagesarch ne "") ) {
                warning " ====== try to read " . dump($imagesarch);
            }
            return(0, '') if ($imagesarch->{tempname} eq "");
            my $zip = Archive::Zip->new($imagesarch->{tempname});
            my $tint = time();
            foreach($zip->members()) {
                my $galtype  = $type || "common";
                
                my $filename = $_->fileName();
                my ( $path, $file, $ext ) = img_fileparse( $filename );
                my $tempname = "/tmp/" . md5_hex(encode_utf8(localtime . $filename)) . ".$ext";
                $zip->extractMemberWithoutPaths( $_, $tempname );
                
                ( $path, $file, $ext ) = img_resize_by_rules( $tempname, $gallery );

                schema->resultset('Image')->create({
                    filename    => img_relative_folder($gallery) . "$file.$ext",
                    imagename   => $filename,
                    remark      => '',
                    type        => $galtype,
                    alias       => $alias,
                });
            }
            return(1, '/gallery/' . $gallery);
        }
    },
};

=head2 :url

Каждый рисунок содержит псевдоним (alias). Эта процедура вытягивает все
рисунки, у которых псевдоним совпадает с заданным на входе.

=cut

any '/gallery/:url' => sub {
    my $url     = param('url');
    my $text    = schema->resultset('Image')->search({ 
            alias => "$url" 
        }, {
            order_by => "id"
        });
    
    if (defined($text)) {
        template 'gallery' => {
            list    => $text,
            url     => $url,
        };
    } else {
        template 'blocks/404' => { 
            title   => 'нет странички',
            url     => $url, 
        };
    }
};

=head2 :url/add

В указанную галерею добавляются записи о новых изображениях и выполняется
переход в точку редактирования рисунка (загрузки и установки его свойств).

=cut

any '/gallery/:url/add' => sub {
    my $url = param('url');
    my $me = schema->resultset('Image')->create({
        filename    => '',
        imagename   => '',
        remark      => '',
        type        => "$url",
        alias       => "$url",
    });
    redirect "gallery/" .$me->id. "/edit";
};

=head2 :url/delete

Указанный по ID рисунок будет удалён.

=cut

any '/gallery/:url/delete' => sub {
    my $parent = "/";
    my $item   = schema->resultset('Image')->find({ id => params->{url} }) || undef;
    if (defined($item)) { 
        $parent  = "/gallery/" . $item->alias || "/";
        my $files = $Bin . "/../public" . img_convert_name($item->filename, "*");
        $item->delete; 
        unlink glob $files;
    };
    redirect $parent;
};

=head2 :id/edit

Выполняет правку рисунка, в т.ч. и загрузку нового.

=cut

fawform '/gallery/:id/edit' =>  {
    template    => 'components/renderform-gallery',
    redirect    => '/',
    formname    => 'image-edit',
    title       => 'Изменить рисунок в галерее',
    fields      => [
    {
        type    => 'text',
        name    => 'id',
        label   => 'id',
        note    => 'идентификатор фотографии (число)',
        default => '',
    },
    {
        type    => 'text',
        name    => 'filename',
        label   => 'имя файла',
        note    => 'имя файла фотографии на сервере',
        default => '',
    },
    {
        type    => 'upload',
        name    => 'imagename',
        label   => 'название фотографии',
        note    => 'название оригинала фотографии',
        default => '',
    },
    {
        type    => 'text',
        name    => 'remark',
        label   => 'комментарий',
        note    => 'комментарий, который может выводиться в подписи к фото',
        default => '',
    },
    {
        type    => 'text',
        name    => 'type',
        label   => 'тип фотографии',
        note    => 'к какому типу изображений относится данная картинка (доп.
        свойство для фильтрации)',
        default => '',
    },
    {
        type    => 'text',
        name    => 'alias',
        label   => 'псевдоним раздела',
        note    => 'к какому разделу прикрепляется эта фотография',
        default => '',
    }
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
        
        my $imagegall = schema->resultset('Image')->find({ id => $id });
        my $imagefile = "";
        my $imagename = "";
        
        if ($_[0] eq "get") {
            if (defined($imagegall)) { 
                # то следует подставить значения по умолчанию из БД.
                $faw->map_params(
                    id          => $imagegall->id || "",
                    filename    => $imagegall->filename || "",
                    imagename   => $imagegall->imagename || "",
                    remark      => $imagegall->remark || "",
                    type        => $imagegall->type || "",
                    alias       => $imagegall->alias || "",
                );
                #$faw->{redirect} = "/gallery/" . $imagegall->alias;
            } else {
                $faw->map_params(
                    id          => "",
                    filename    => "",
                    imagename   => "",
                    remark      => "",
                    type        => "",
                    alias       => "",
                );
            };
        };

        if ($_[0] eq "post") {
            return(1, "/gallery/" . params->{alias} ) if (params->{submit}  eq "Отменить");
            if (defined( request->{uploads}->{imagename} )) {
                my $galtype  = params->{type} || "common";
                my $upload   = request->{uploads}->{imagename};
                
                my $filetemp = $upload->{tempname};
                
                my $filename = $upload->{filename};
                my ( $path, $file, $ext ) = img_fileparse( $filename );
                ( $path, $file, $ext ) = img_resize_by_rules( $filetemp, $galtype );

                $imagegall->update({
                    filename    => img_relative_folder($galtype) . "$file.$ext",
                    imagename   => $filename,
                });
            };
                
            $imagegall->update({
                remark      => params->{remark},
                type        => params->{type},
                alias       => params->{alias},
            });
            return (1, "/gallery/" . params->{alias});
        };
        
        $faw->{action}   = $path;
    },
};

=head2 :id/refresh

Обновить изображение согласно новым правилам.

Сначала следует найти изображение наибольшего размера, а затем преобразовать
его в масштабируемый вид.

=cut

get '/gallery/:id/refresh' => sub {
    my $id      = params->{id};
    my $item    = schema->resultset('Image')->find({
            id => $id }) || undef;
    my $parent  = "/";
    my $files;
    my ( $path, $file, $ext );
    my ( $bestfile, $size ) = ( "", 0 );
    if ( defined($item) ) {
        $parent = "/gallery/" . $item->alias || "/";
        ( $path, $file, $ext ) = img_fileparse($item->filename);
        $files = $Bin . "/../public" . $path . $file . "*." . $ext;
        warning " ============= $files ";
        foreach my $tempname ( glob($files) ) {
            if ( -s $tempname > $size ) { $bestfile = $tempname; $size = -s $tempname; }
        }
        warning " ============= use $bestfile for resize ";
        copy $bestfile, "/tmp/$file.$ext";
        unlink glob $files;
        img_resize_by_rules( "/tmp/$file.$ext", $item->alias );
    };
    redirect $parent;
};

=head2 before_template_render

Внедрение процедур для использования в шаблонах.

=cut

hook before_template_render => sub {
    my ( $tokens ) = @_;
    $tokens->{gallery} = \&gallery;
};

our $createsql = qq|
CREATE TABLE IF NOT EXISTS images (
    id        int(10) NOT NULL AUTO_INCREMENT, 
    filename  varchar(255) NOT NULL, 
    imagename varchar(255), 
    remark    varchar(255), 
    type      varchar(32), 
    alias     varchar(255) NOT NULL,
    PRIMARY KEY (id)
) CHARACTER SET = utf8;
|;

true;
