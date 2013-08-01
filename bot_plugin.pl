use 5.010;
use strict;
use BotImpl;

use vars qw($handle $conclude $addaction $heartbeat $stdout $last_id $whoami $store $shutdown $extension_mode $EM_SCRIPT_OFF);
$extension_mode = $EM_SCRIPT_OFF;

my $bot = BotImpl->new('tweets.brn');
$bot->load_config({ last_tweet_id => \$last_id });
setvariable('dostream', 1);
setvariable('ssl', 1);
setvariable('slowpost', 2);
setvariable('streamallreplies', 1) if $bot->settings->{src_username};

$handle = sub {
    my ($tweet, $source_cmd) = @_;
    handle_ext_settings();
    goto END if $source_cmd;                            # skip duplicated tweets
    goto END if $tweet->{user}->{protected} eq 'true';  # skip protected tweets
    goto END if defined $tweet->{retweeted_status};     # skip RT's
    my $user = descape($tweet->{user}->{screen_name});
    goto END if $user eq $whoami;                       # skip own tweets
    my $text = descape($tweet->{text});
    if ($bot->settings->{answer_replies})               # if enabled, answer replies
    {
        my $reply_to = descape($tweet->{in_reply_to_screen_name});
        if ($reply_to eq $whoami)
        {
            my $at_str = "\@$user ";
            my $msg = $at_str . $bot->reply($text, 140 - length($at_str));
            updatest($msg, 0, $tweet->{id_str});
        }
    }
    goto END if $bot->is_filtered_user($user);          # if enabled, listen to a single user
    $bot->learn($text);
END:
    defaulthandle($tweet);
    return 1;
};

$conclude = sub {
    handle_ext_settings(1);
    defaultconclude();
};

$heartbeat = sub {
    handle_ext_settings();
    return if !$bot->can_tweet;
    my $msg = $bot->reply;
    #say $stdout "-- bot reply: $msg";
    updatest($msg);
};

$shutdown = sub {
    handle_ext_settings(1);
};

# this runs on a different process, so we see $store as it was before the process fork'ed
$addaction = sub {
    my ($cmd) = @_;
    if ($cmd =~ /^\/botctl\s?(.*)/)
    {
        my ($key, $val) = split /\s+/, $1;
        if (!exists $bot->settings->{$key})
        {
            say $stdout "-- invalid key '$key'";
            return 1;
        }
        say $stdout "-- botctl '$key' = '$val'";
        sendbackgroundkey($key, $val); # this assigns `$store{$key} = $val` on the main process
        return 1;
    }
    return 0;
};

# applies the settings sent via sendbackgroundkey()
sub handle_ext_settings
{
    my ($do_save) = @_;
    while (my ($key, $val) = each %$store)
    {
        next if $key eq 'loaded';   # set by ttytter, don't touch
        $bot->settings->{$key} = defined $val ? $val : '';
        delete $store->{$key};
        $do_save = 1;
    }
    $bot->save_config({ last_tweet_id => $last_id }) if ($do_save);
}
