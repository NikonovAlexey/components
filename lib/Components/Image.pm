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

our $VERSION = '0.01';

prefix '/';

=head IMAGES

Обеспечивает операции над изображениями.

=cut

any '/images/:id' => sub {

};

true;
