package BotImpl;
use 5.010;
use strict;
use DBI;
use Text::CSV_XS;
use HTML::Entities;
use Regexp::Common qw(URI);
use DateTime;
use Hailo;

sub new
{
    my ($class, $file) = @_;
    my $self = {
        brain_file => $file,
        settings => {
            last_tweet_id => 0,
            src_username => '',
            tweet_interval => 15,
            last_tweet_time => '',
            tweet_chance => 100,
            answer_replies => 0,
        },
    };
    bless $self, $class;
    return $self;
}

sub bot
{
    return $_[0]->{bot};
}

sub settings
{
    return $_[0]->{settings};
}

sub init_bot
{
    my $self = shift;
    return if $self->bot;
    $self->{bot} = Hailo->new(brain => $self->{brain_file}, @_);
}

sub unload_bot
{
    my ($self) = @_;
    return if !$self->bot;
    $self->bot->save;
    undef $self->{bot};
}

# parses a twitter's tweets.csv file and learns it
sub learn_file
{
    my ($self, $in_file) = @_;
    my $csv = Text::CSV_XS->new({ binary => 1, empty_is_undef => 1 });
    open my $fh, '<:encoding(utf8)', $in_file or die "error opening $in_file: $!\n";

    $self->unload_bot;
    $self->init_bot(storage_args => { in_memory => 1 });
    my $last_tweet_id;

    for (my $row, my $line; $row = $csv->getline($fh); ++$line)
    {
        next if !$line or defined $row->[3];      # skip first line and RTs
        $last_tweet_id = $row->[0] if $line == 1; # save last tweet id
        my $tweet = _filter_tweet(decode_entities($row->[7]));
        next if !length($tweet);                  # skip empty lines after filtering
        $self->bot->learn($tweet);
    }

    close $fh;
    $self->unload_bot;

    # inject additional settings into the brain database
    $self->save_config({ last_tweet_id => $last_tweet_id });
}

# learns from a string of text
sub learn
{
    my ($self, $raw_text) = @_;
    my $text = _filter_tweet($raw_text);
    $self->bot->learn($text);
    $self->settings->{last_learned_str} = $text;
}

# generates a random reply, related to $text if defined
sub reply
{
    my ($self, $raw_text, $max_len) = @_;
    my $text = _filter_tweet($raw_text) if defined $raw_text;
    $max_len = 140 if !defined $max_len;
    my $msg = $self->bot->reply($text);
    # remove last words if generated text is longer than $max_len characters
    if ($max_len > 0)
    {
        $msg =~ s/\s+\S+\s*$// while (length $msg > $max_len);
    }
    return $msg;
}

# removes @usernames and URL's from a string
sub _filter_tweet
{
    my ($str) = @_;
    $str =~ s/@\w+//g;          # strip usernames
    $str =~ s/$RE{URI}//g;      # strip URLs
    $str =~ s/\s{2,}/ /g;       # remove double spaces
    $str =~ s/^\s+|\s+$//g;     # trim
    return $str;
}

# if enabled, listens to tweets only from the user we're currently tracking (src_username)
sub is_filtered_user
{
    my ($self, $user) = @_;
    return $self->settings->{src_username} ? $user ne $self->settings->{src_username} : 0;
}

# defines when the bot can tweet and the tweet frequency
sub can_tweet
{
    my ($self) = @_;
    # tweet only from 12pm to 12am
    my $now = DateTime->now(time_zone => 'local');
    return 0 if $now->hour >= 0 && $now->hour < 12;
    # check time interval between tweets
    if ($self->settings->{tweet_interval} and $self->settings->{last_tweet_time})
    {
        my $diff = $now->delta_ms(_parse_datetime($self->settings->{last_tweet_time}));
        return 0 if $diff->{minutes} < $self->settings->{tweet_interval};
    }
    # save last tweet attempt time
    $self->settings->{last_tweet_time} = _serialize_datetime($now);
    # roll chance for tweeting
    return rand(100) < $self->settings->{tweet_chance};
}

# construct a DateTime object from a string
sub _parse_datetime
{
    my ($str) = @_;
    my @parts = split ',', $str;
    die 'invalid argument' if @parts != 6;
    return DateTime->new(time_zone => 'local', map { $_ => shift @parts } qw(year month day hour minute second));
}

# convert a DateTime object into a string
sub _serialize_datetime
{
    my ($dt) = @_;
    return $dt->ymd(',') . "," . $dt->hms(',')
}

# opens the brain file as a SQLite database to load/store additional settings
sub _open_db
{
    my ($self) = @_;
    return DBI->connect("dbi:SQLite:dbname=$self->{brain_file}", '', '', { RaiseError => 1 });
}

sub load_config
{
    my ($self, $ext_vars) = @_;
    my $db = $self->_open_db();
    my $st = $db->prepare('SELECT text FROM info WHERE attribute = ?');
    for (keys %{$self->settings})
    {
        $st->execute($_);
        if (my $row = $st->fetch)
        {
            $self->settings->{$_} = $row->[0];
        }
        $st->finish;
    }
    $db->disconnect;

    # write values into the passed references (conf_key => \$external_var)
    if (defined $ext_vars)
    {
        ${$ext_vars->{$_}} = $self->settings->{$_} for (keys %$ext_vars);
    }
}

sub save_config
{
    my ($self, $ext_vars) = @_;
    # read values from the passed variables (conf_key => $external_var)
    if (defined $ext_vars)
    {
        $self->settings->{$_} = $ext_vars->{$_} for (keys %$ext_vars);
    }

    my $db = $self->_open_db();
    my $st = $db->prepare('INSERT OR REPLACE INTO info (attribute, text) VALUES (?,?)');
    $st->execute($_, $self->settings->{$_}) for (keys %{$self->settings});
    $db->disconnect;
}

1;
