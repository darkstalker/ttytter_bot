#!/usr/bin/perl
use 5.010;
use strict;
use BotImpl;
binmode STDOUT, ':utf8';

my $brain_file = 'tweets.brn';
#die if !-f $brain_file;

my $bot = BotImpl->new($brain_file);
$bot->init_bot;
say $bot->reply(join ' ', @ARGV);
