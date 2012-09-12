package Gallery;

use Dancer ':syntax';

use Dancer::Plugin::DBIC;
use Dancer::Plugin::FAW;
use Dancer::Plugin::uRBAC;

use Image::Magick;
use Digest::MD5 qw(md5_hex);
use FindBin qw($Bin);

our $VERSION = '0.05';

prefix '/gallery';

any '/' => sub {
    my $gallist = schema->resultset('Image')->search(undef, {
        select => [ { distinct => 'alias' } ],
        order_by => 'alias',
    });

    template 'components/gallist' => {
        gallist => $gallist,
    };
};

any '/:url' => sub {
    my $url     = param('url');
    my $text    = schema->resultset('Image')->search({ alias => "$url" });
    
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

any '/:url/add' => sub {
    my $url = param('url');
    
    if ( rights('admin') ) {
        my $me = schema->resultset('Image')->create({
            filename    => '',
            imagename   => '',
            remark      => '',
            type        => 'top-banner',
            alias       => "$url",
        });
        redirect "gallery/" .$me->id. "/edit";
    } else {
        redirect "gallery/$url";
    };
};

any '/:url/delete' => sub {
    my $parent = "/";
    my $item   = schema->resultset('Image')->find({ id => params->{url} }) || undef;
    if ( rights('admin') ) { 
        if (defined($item)) { 
            $parent  = "/gallery/" . $item->alias || "/";
            my $file    = $item->filename;
            $item->delete; 
            unlink $Bin . "/../public" . $file;
        };
    };
    redirect $parent;
};

fawform '/:url/edit' =>  {
    template    => 'components/renderform',
    redirect    => '/',
    layout      => 'edit', 

    formname    => 'image-edit',
    fields      => [
    {
        type    => 'text',
        name    => 'id',
        label   => 'id',
        note    => 'идентификатор фотографии (число)'
    },
    {
        type    => 'text',
        name    => 'filename',
        label   => 'имя файла',
        note    => 'имя файла фотографии на сервере',
    },
    {
        type    => 'upload',
        name    => 'imagename',
        label   => 'название фотографии',
        note    => 'название оригинала фотографии'
    },
    {
        type    => 'text',
        name    => 'remark',
        label   => 'комментарий',
        note    => 'комментарий, который может выводиться в подписи к фото',
    },
    {
        type    => 'text',
        name    => 'type',
        label   => 'тип фотографии',
        note    => 'к какому типу изображений относится данная картинка (доп.
        свойство для фильтрации)'
    },
    {
        type    => 'text',
        name    => 'alias',
        label   => 'псевдоним раздела',
        note    => 'к какому разделу прикрепляется эта фотография',
    }
    ],
    buttons     => [
        {
            name        => 'submit',
            value       => 'Применить'
        },
    ],
    before      => sub {
        my $faw  = ${$_[1]};
        my $path = params->{url};

        if ($_[0] eq "get") {
            my $image = schema->resultset('Image')->find({ id => $path });
            if (defined($image)) { 
                # то следует подставить значения по умолчанию из БД.
                $faw->map_params(
                    id          => $image->id,
                    filename    => $image->filename,
                    imagename   => $image->imagename,
                    remark      => $image->remark,
                    type        => $image->type,
                    alias       => $image->alias,
                );
                $faw->{redirect} = "/gallery/" . $image->alias;
            } else {
                # или же (когда такой записи ещё нет в БД) то просто установить
                # текущий путь, т.е. использовать вычисляемые значения по умолчанию.
                #$faw->map_params(url => $path);
            };
        };
        $faw->{action}   = "/gallery/$path/edit";
    },
    after       => sub { if ($_[0] =~ /^post$/i) {
        my $imagegall = schema->resultset('Image')->find({ id => params->{id} }) || undef;
        if (defined( request->{uploads}->{imagename} )) {
            my $upload = request->{uploads}->{imagename};
            
            my $filename = $upload->{filename};
            my $filetemp = $upload->{tempname};
            my $filesize = $upload->{size};
            my ( $image, $x, $y, $k );
            
            $filename    =~ /\.(\w{3})/;
            my $fileext  = lc($1) || "png";
            
            my $destpath =  "/images/galleries/";
            my $destfile = "" . md5_hex($filetemp . $filesize);
            my $abspath  = $Bin . "/../public" . $destpath;
            
            #move($filetemp, $abspath . $destfile);
            
            # прочтём рисунок и его параметры
            $image      = Image::Magick->new;
            $image->Read($filetemp);
            # масштабируем и запишем
            $image->Resize(geometry => '601x182');
            $image->Write($abspath . $destfile . ".$fileext");
            
            if (defined( $imagegall )) {
                $imagegall->update({
                    filename   => "${destpath}${destfile}.$fileext" || "",
                    imagename   => params->{imagename} || "",
                    remark      => params->{remark} || "",
                    type        => params->{type} || "",
                    alias       => params->{alias} || "",
                });
            } else {
                schema->resultset('Image')->create({
                    filename   => "${destpath}${destfile}.$fileext" || "",
                    imagename   => params->{imagename} || "",
                    remark      => params->{remark} || "",
                    type        => params->{type} || "",
                    alias       => params->{alias} || "",
                });
            };
        };
    } },
};

# Подготовка общей инфы для всех страничек
hook before_template_render => sub {
    my ( $tokens ) = @_;
    $tokens->{gallery} = \&gallery;
};

sub gallery {
    my ( $s, $t, $engine, $out );

    ( $s, $t ) = @_; $s ||= ""; return "" if ($s eq "");
    $t ||= "top-banner";
    
    my $items = schema->resultset('Image')->search({ 
            alias => $s,
            type => $t
        }, {
            order_by => { -asc => 'id' },
        });
    $engine = Template->new({ INCLUDE_PATH => $Bin . '/../views/' });
    $engine->process('components/gallery.tt', { s => $s, gallery => $items, rights => \&rights }, \$out);

    return $out;
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
