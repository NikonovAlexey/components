package Documents;

use Dancer ':syntax';

use Dancer::Plugin::DBIC;
use Dancer::Plugin::FAW;
use Dancer::Plugin::uRBAC;
use Dancer::Plugin::FlashNote;

use Try::Tiny;
use FindBin qw($Bin);
use File::Copy "cp";
use Digest::MD5 qw(md5_hex);
use Data::Dump qw(dump);
use Encode qw(encode_utf8);

our $VERSION = '0.08';

prefix '/';

any '/docs/:id/delete' => sub {
    my $alias = "/";
    try {
        my $item = schema->resultset('Document')->single({
            id => params->{id}
        });
        $alias = "/page/" . $item->alias;
        unlink($Bin . "/../public" . $item->filename);
        $item->delete;
    } catch {
        warning " unable to remove file " . params->{id};
    };
    redirect $alias;
};

fawform '/docs/:alias/add' => {
    template    => 'components/document-add',
    redirect    => '/',
    formname    => 'document-add',
    title       => 'Прикрепить документ к разделу',
    
    fields      => [
    {
        type    => 'upload',
        name    => 'docname',
        label   => 'файл документа',
        note    => 'укажите документ на вашем компьютере',
        default => '',
    },
    {
        type    => 'text',
        name    => 'remark',
        label   => 'комментарий',
        note    => 'добавьте описание документа',
        default => '',
    },
    {
        type    => 'text',
        name    => 'alias',
        label   => 'псевдоним раздела',
        note    => 'к какому разделу прикрепляется этот документ',
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
        my $alias= params->{alias};
        my $path = $faw->fieldset(":alias" => $alias);
        
        if ($_[0] eq "get") { $faw->map_params( alias => $alias ); };
        
        if ($_[0] eq "post") {
            return(1, "/page/$alias") if (params->{submit}  eq "Отменить");
            
            my ( $upload, $srcfile, $fileext, $alias );
            my ( $destination, $absolute, $destfile );
            
            $upload      = request->{uploads}->{docname};
            $srcfile     = $upload->{tempname};
            $srcfile     =~ /\.(\w{2,5})$/;
            $fileext     = lc($1) || "odt";
            $alias       = params->{alias};
            
            $destination = config->{components}->{documents}->{destination}
                            || "upload-docs";
            $destination    = "/$destination/$alias/";
            $absolute    = "$Bin/../public$destination";
            $destfile    = "" . md5_hex(encode_utf8($srcfile), $upload->{size}) .  ".$fileext";
            
            try {
                if ( ! -e $absolute ) { mkdir $absolute };
                cp($srcfile, $absolute . $destfile);
            } catch {
                #flash "Не получилось скопировать файл на сервер.";
                return(0,'');
            };

            try {
                schema->resultset("Document")->create({
                    filename    => $destination . $destfile,
                    docname     => $upload->{filename},
                    remark      => params->{remark},
                    alias       => $alias, 
                });
                return(1, "/page/$alias");
            } catch {
                #flash "Не получилось записать информацию о файле в базу данных";
            };
            
            #return(0, "");
            return(1, "/page/$alias");
        };
    },
};

fawform '/docs/:id/edit' => {
    template    => 'components/document-add',
    redirect    => '/',
    formname    => 'document-add',
    title       => 'Изменить описание документа',
    
    fields      => [
    {
        type    => 'text',
        name    => 'remark',
        label   => 'комментарий',
        note    => 'исправьте описание документа',
        default => '',
    },
    {
        type    => 'text',
        name    => 'alias',
        label   => 'псевдоним раздела',
        note    => 'к какому разделу прикрепляется этот документ',
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
        my $doc  = schema->resultset('Document')->find({ id => $id });
        my $alias= $doc->alias;
        
        if ($_[0] eq "get") { 
            $faw->map_params( 
                alias => $alias,
                remark => $doc->remark,
            ); 
        };
        
        if ($_[0] eq "post") {
            $doc->update({
                remark => params->{remark},
            });

            return(1, "/page/$alias");
        };
    },
};

# Подготовка общей инфы для всех страничек
hook before_template_render => sub {
    my ( $tokens ) = @_;
    $tokens->{documents} = \&documents;
};

sub documents {
    my ( $alias ) = @_;
    my ( $engine, $out );
    
    my $items = schema->resultset("Document")->search({ 
        alias => $alias 
    },{
        order_by => "id"
    });
    return "" if ( $items->count == 0 );
    
    return template_process('documents.tt', {
            documents   => $items,
            rights      => \&rights,
        });
};

our $createsql = qq|
CREATE TABLE IF NOT EXISTS documents (
    id        int(10) NOT NULL AUTO_INCREMENT, 
    filename  varchar(255) NOT NULL, 
    docname   varchar(255), 
    remark    varchar(255), 
    alias     varchar(255) NOT NULL,
    PRIMARY KEY (id)
) CHARACTER SET = utf8;
|;

true;
