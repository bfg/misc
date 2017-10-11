#!/usr/bin/env perl

use strict;
use warnings;

use File::Spec;
use Date::Parse;
use Image::EXIF;
use Data::Dumper;
use Getopt::Long;
use File::Basename;
use File::Copy qw(move);
use POSIX qw(strftime);

###########################################################
#                        CONFIG                           #
###########################################################

my $file_prefix = "img-";
my $do_it = 0;
my $lowecase = 1;
my $use_mtime = 0;
my $date_pattern = "%Y-%m-%d_%H-%M-%S";

###########################################################
#                      FUNCTIONS                          #
###########################################################

my $MYNAME = basename($0);
my $counter = 0;

sub is_image {
  my $file = shift;
  return ($file =~ m/\.(?:jpg|jpeg|png)$/i);
}

sub is_video {
  return ($_[0] =~ m/\.(?:mpg|mpeg|mp4|m4p|m3v|3gp|3g2|avi|mov|qt|webm|mkv|flv|vob|ogv|ogg|wmv)$/i);
}

sub compute_new_filename {
  my ($file, $file_mtime) = @_;

  my $dirname = dirname($file);
  my $basename = basename($file);
  my $suffix = $basename =~ s/.*\.(\w{3,4})$/$1/ri;

  my $i = -1;
  while (++$i < 1000) {
    my $index_suffix = ($i == 0) ? "" : "-" . $i;
    my $strftime_pattern = $file_prefix . $date_pattern . $index_suffix . "." . $suffix;
    my $new_basename = strftime($strftime_pattern, localtime($file_mtime));
    $new_basename = lc($new_basename) if ($lowecase);

    my $new_fullname = File::Spec->catfile($dirname, $new_basename);
    return $new_fullname unless (-f $new_fullname);

    warn("$file: destination already exists: $new_fullname\n");
  }

  return undef;
}

sub get_create_time {
  my ($file) = @_;

  if (is_image($file)) {
    return get_create_time_image($file);
  }
  elsif (is_video($file)) {
    return stat_mtime($file);
  }

  return -1;
}

sub get_create_time_image {
  my ($file) = @_;

  # try exif first
  my $exif = Image::EXIF->new($file);
  my $image_info = $exif->get_image_info();
  my $created = $image_info->{'Image Created'};
  if ($created) {
    # convert to unix time
    my $time = str2time($created);
    return $time if ($time > 0);
  }

  # maybe we're allowed to use mtime?
  if ($use_mtime) {
    return stat_mtime($file);
  }

  -1;
}

sub stat_mtime {
  my @stat = stat($_[0]);
  $stat[9];
}

sub process_file {
  my $file = shift;
  unless (is_image($file) || is_video($file)) {
    warn("$file: not an image or video\n");
    return 1
  }

  # get creation time
  my $time_created = get_create_time($file);
  return 0 unless ($time_created);

  # compute new filename
  my $new_fullname = compute_new_filename($file, $time_created);
  unless (defined $new_fullname) {
    warn("$file: cannot compute available filename.\n");
    return 0;
  }

  print "moving: $file => $new_fullname\n";
  if ($do_it) {
    unless (move($file, $new_fullname)) {
      warn("$file: error moving to $new_fullname: $!\n");
      return 0;
    }
  }
  return 1;
}

sub printhelp {
  print <<EOF
Usage: $MYNAME [OPTIONS] file file ...

This script renames files based on EXIF image created data.

OPTIONS:
  -p  --prefix=PREFIX         Filename prefix (default: "$file_prefix")
  -d  --date-pattern=PATTERN  strftime(3) pattern for formatting filename (default: "$date_pattern")

  -m  --use-mtime             Use file modification time if EXIF date is not available
      --no-lowercase          Don't lowercase filenames
  -Y  --do-it                 Really perform file renames

  -h  --help                  This help message
EOF
}

###########################################################
#                          MAIN                           #
###########################################################

# parse command line arguments.
Getopt::Long::Configure("bundling", "permute", "bundling_override");
my $g = GetOptions(
  'p|prefix=s'        => \$file_prefix,
  'd|date-pattern=s'  => \$date_pattern,
  'm|use-mtime!'      => \$use_mtime,
  'lowercase!'        => \$lowecase,
  'Y|do-it'           => \$do_it,
  'h|help'            => sub { printhelp(); exit 0 },
);
die "Invalid command line options. Run $MYNAME --help for instructions\n" unless ($g);

# process all files
map { process_file($_) } @ARGV;

# vim: shiftwidth=2 softtabstop=2 expandtab
# EOF
