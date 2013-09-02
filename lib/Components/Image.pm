package Images;

use Dancer ':syntax';

use Dancer::Plugin::DBIC;
use Dancer::Plugin::FAW;
use Dancer::Plugin::uRBAC;

use Image::Magick;
use Digest::MD5 qw(md5_hex);
use FindBin qw($Bin);
use Try::Tiny;
use Data::Dump qw(dump);

use Archive::Zip;

our $VERSION = '0.08';

prefix '/';

=head IMAGES

Обеспечивает операции над изображениями.

=cut

=head1 Вспомогательные процедуры

=cut

=head2 parsename 

Разберём имя файла на путь, имя и расширение

=cut

sub parsename {
    my $filename = shift;
    
    $filename    =~ /\.(\w{2,4})$/;
    my $fileext  = lc($1) || "png";

    my $destpath =  "/images/galleries/" . $galtype . "/";
    my $abspath  = $Bin . "/../public" . $destpath;
    
    my $galtype  = $type || "common";
    my $resizeto = config->{plugins}->{gallery}->{$galtype} || "601x182";

    my $upload   = request->{uploads}->{imagename};

    my $filename = $_->fileName();
    my $filetemp = $_->fileName();
    my $filesize = $_->compressedSize();

    my ( $image, $x, $y, $k );

    $filename    =~ /\.(\w{2,4})$/;
    my $fileext  = lc($1) || "png";

    my $destpath =  "/images/galleries/" . $galtype . "/";
    my $destfile = "" . md5_hex($filetemp . $filesize);
    my $abspath  = $Bin . "/../public" . $destpath;
    if ( ! -e $abspath ) { mkdir $abspath; }

    my $destination = "$abspath$destfile.$fileext";
    $zip->extractMemberWithoutPaths( $_, $destination );

    # прочтём рисунок и его параметры
    $image      = Image::Magick->new;
    $image->Read($destination);
    
    # масштабируем и запишем
    $image->Resize(geometry => $resizeto) if ($resizeto ne "noresize");
    $image->Write($destination);

    schema->resultset('Image')->create({
    filename    => "$destpath$destfile.$fileext",
    imagename   => $_->fileName(),
    remark      => '',
    type        => $type,
    alias       => $alias,
    });
    return ($path, $name, $ext);
}

sub resize {
    my ( $imagename, $suffix, $destsize ) = ( shift, shift, shift );

}



any '/images/:id' => sub {

};

true;
