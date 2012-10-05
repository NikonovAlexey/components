package Gallery;

use Dancer ':syntax';

use Dancer::Plugin::DBIC;
use Dancer::Plugin::FAW;
use Dancer::Plugin::uRBAC;

use Image::Magick;
use Digest::MD5 qw(md5_hex);
use FindBin qw($Bin);
use Try::Tiny;

our $VERSION = '0.06';

prefix '/gallery';

any '/list' => sub {
    my $gallist = schema->resultset('Image')->search(undef, {
        select => [ 'alias', 'type' ],
        distinct => 1,
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
            type        => "$url",
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

fawform '/:id/edit' =>  {
    template    => 'components/renderform-gallery',
    redirect    => '/',

    formname    => 'image-edit',
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
            if (defined( request->{uploads}->{imagename} )) {
                my $upload = request->{uploads}->{imagename};
                
                my $filename = $upload->{filename};
                my $filetemp = $upload->{tempname};
                my $filesize = $upload->{size};
                my $galtype  = params->{type} || "common";
                my $resizeto = config->{plugins}->{gallery}->{$galtype} || "601x182";
                my ( $image, $x, $y, $k );
                
                $filename    =~ /\.(\w{3})/;
                my $fileext  = lc($1) || "png";
                
                my $destpath =  "/images/galleries/" . $galtype . "/";
                my $destfile = "" . md5_hex($filetemp . $filesize);
                my $abspath  = $Bin . "/../public" . $destpath;
                if ( ! -e $abspath ) { mkdir $abspath; }
                
                #move($filetemp, $abspath . $destfile);
                
                # прочтём рисунок и его параметры
                $image      = Image::Magick->new;
                $image->Read($filetemp);
                # масштабируем и запишем
                $image->Resize(geometry => $resizeto) if ($resizeto ne "noresize");
                $image->Write($abspath . $destfile . ".$fileext");

                $imagefile = $destpath . $destfile . "." . $fileext;
                $imagename = params->{imagename};
                $imagegall->update({
                    filename    => $imagefile,
                    imagename   => $imagename,
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

# Подготовка общей инфы для всех страничек
hook before_template_render => sub {
    my ( $tokens ) = @_;
    $tokens->{gallery} = \&gallery;
};

sub gallery {
    my ( $s, $t, $engine, $out );
    my $items;

    ( $s, $t ) = @_; $s ||= ""; 
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
    } else {
        $items = "";
    }
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
