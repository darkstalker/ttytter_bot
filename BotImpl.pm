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
    my $self = { brain_file => $file, last_tweet_id => 0, src_username => '' };
    bless $self, $class;
    return $self;
}

sub bot
{
    return $_[0]->{bot};
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
    my $db = $self->_open_db;
    my $st = $db->prepare('INSERT INTO info (attribute, text) VALUES (?,?)');
    $st->execute('last_tweet_id', $last_tweet_id);
    $db->disconnect;
}

# learns from a string of text
sub learn
{
    my ($self, $text) = @_;
    $self->bot->learn(_filter_tweet($text));
}

# generates a random reply, related to $text if defined
sub reply
{
    my ($self, $text) = @_;
    my $msg = $self->bot->reply($text);
    # remove last words if generated text is longer than 140 characters
    $msg =~ s/\s+\S+\s*$// while (length $msg > 140);
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

# implements the single user listening setting
sub is_filtered_user
{
    my ($self, $user) = @_;
    return $self->{src_username} and $user ne $self->{src_username};
}

# defines when the bot can tweet and the tweet frequency
sub can_tweet
{
    my ($self, $chance) = @_;
    $chance = 100 if !defined $chance;
    # tweet only from 12pm to 12am
    my $hour = DateTime->now(time_zone => 'local')->hour;
    return 0 if $hour >= 0 && $hour < 12;
    #TODO: define a better method for setting the tweet frequency
    return rand(100) < $chance;
}

# opens the brain file as a SQLite database to load/store additional settings
sub _open_db
{
    my ($self) = @_;
    return DBI->connect("dbi:SQLite:dbname=$self->{brain_file}", '', '', { RaiseError => 1 });
}

sub load_config
{
    my ($self, $last_id_ref) = @_;
    my $db = $self->_open_db();
    my $st = $db->prepare('SELECT text FROM info WHERE attribute = ?');
    for (qw(last_tweet_id src_username))
    {
        $st->execute($_);
        if (my $row = $st->fetch)
        {
            $self->{$_} = $row->[0];
        }
        $st->finish;
    }
    $db->disconnect;
    $$last_id_ref = $self->{last_tweet_id}; #TODO: better way of accessing the global var
}

sub save_config
{
    my ($self, $last_id) = @_;
    $self->{last_tweet_id} = $last_id;
    my $db = $self->_open_db();
    my $st = $db->prepare('INSERT OR REPLACE INTO info (attribute, text) VALUES (?,?)');
    for (qw(last_tweet_id src_username))
    {
        $st->execute($_, $self->{$_});
    }
    $db->disconnect;
}

1;
