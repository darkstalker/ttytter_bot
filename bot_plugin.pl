use 5.010;
use strict;
use BotImpl;

use vars qw($handle $conclude $addaction $heartbeat $store $stdout $last_id $whoami $extension_mode $EM_SCRIPT_OFF);
$extension_mode = $EM_SCRIPT_OFF;

$store->{bot} = BotImpl->new('tweets.brn');
$store->{bot}->load_config({ last_tweet_id => \$last_id });
$store->{bot}->init_bot;

$handle = sub {
    my ($tweet, $source_cmd) = @_;
    goto END if $source_cmd;                            # skip duplicated tweets
    goto END if $tweet->{user}->{protected} eq 'true';  # skip protected tweets
    goto END if defined $tweet->{retweeted_status};     # skip RT's
    my $user = descape($tweet->{user}->{screen_name});
    goto END if $user eq $whoami;                       # skip own tweets
    goto END if $store->{bot}->is_filtered_user($user); # if enabled, listen to a single user
    my $text = descape($tweet->{text});
    $store->{bot}->learn($text);
END:
    defaulthandle($tweet);
    return 1;
};

$conclude = sub {
    $store->{bot}->save_config({ last_tweet_id => $last_id });
    defaultconclude();
};

$heartbeat = sub {
    return if !$store->{bot}->can_tweet;
    my $msg = $store->{bot}->reply;
    #say $stdout "-- bot reply: $msg";
    updatest($msg);
};

=rem
# can't use this due to a ttytter bug (we get a different $store instance here)
$addaction = sub {
    my ($cmd) = @_;
    if ($cmd =~ /^\/botreply\s?(.*)/)
    {
        say $stdout "-- bot reply '$1'";
        my $msg = $store->{bot}->reply($1);
        updatest($msg);
        return 1;
    }
    elsif ($cmd =~ /^\/botsrc\s?(.*)/)
    {
        say $stdout "-- bot src_username = '$1'";
        $store->{bot}->{src_username} = $1;
        return 1;
    }
    elsif ($cmd =~ /^\/save\s?(.*)/)
    {
        $store->{bot}->save_config({ last_tweet_id => $last_id });
        return 1;
    }
    return 0;
};
=cut
