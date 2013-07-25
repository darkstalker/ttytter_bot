#!/usr/bin/perl
use 5.010;
use strict;
use BotImpl;

my $in_file  = ($ARGV[0] or 'tweets.csv');
my $out_file = ($ARGV[1] or 'tweets.brn');
die "output file '$out_file' already exists, won't overwrite.\n" if -f $out_file;

say "Learning from '$in_file', saving to '$out_file'...";
my $bot = BotImpl->new($out_file);
$bot->learn_file($in_file);
say "Success.";
