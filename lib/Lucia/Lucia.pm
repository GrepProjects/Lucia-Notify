package Lucia::Lucia;

use strict;
use warnings;

use Storable qw(store retrieve);

use Lucia::Defaults;
use Lucia::ProtoTTS;
use Lucia::Dictionary;
use Lucia::Debugger;
use Lucia::Notification::Notify;
use Lucia::BugChurch::Proxy;


our %LUCIA_VOICES = (
    es => 'Lucia',
    en => 'Kimberly'
);

sub new {

    my $class = shift;

    my $self = {

        _time         => DEFAULT_TIME_PER_QUERY,
        _voice_engine => undef,
        _sound        => DEFAULT_SOUND,
        _lang         => DEFAULT_LANGUAGE,
        _debug        => DEFAULT_DEBUG,
        _nogreeting   => DEFAULT_NO_GREETING, 

        _bcp          => Lucia::BugChurch::Proxy->new,
        _notify       => Lucia::Notification::Notify->new,
        _dict         => Lucia::Dictionary->new,
        _debug        => DEFAULT_DEBUG

    };

    bless $self, $class;

    $self->_create_bug_box();

    return $self;

}

sub _create_bug_box {

    my $self = shift;
    
    if ( ! -e BUG_BOX_NAME ) {
        store {}, BUG_BOX_NAME; 
    }

    $self->{_bug_box} = retrieve(BUG_BOX_NAME);

    return;

}

sub set_time {

    my ( $self, $time ) = @_;

    die "[x] That time is nonsense, something coherent please\n"
      unless $time >= MIN_TIME_PER_QUERY;
    $self->{_time} = $time;

    return;

}

sub set_lang {

    my ( $self, $lang ) = @_;
    $self->{_lang} = $lang;
    return;

}

sub active_sound {

    my ( $self, $is_active ) = @_;

    die "[x] Please provide 1 or 0\n" unless $is_active =~ /^[01]$/;
    $self->{_sound} = $is_active;

    return;

}

sub active_voice {

    my ( $self, $is_active ) = @_;

    die "[x] Please provide 1 or 0\n" unless $is_active =~ /^[01]$/;
    $self->{_voice_engine} = Lucia::ProtoTTS->new if $is_active;

    return;

}

sub set_language {

    my ( $self, $lang ) = @_;

    die "[x] I don't speak that language\n"
      unless exists $LUCIA_VOICES{$lang};
    $self->{_lang} = $lang;

    return;

}

sub active_debug {

    my ( $self, $is_active ) = @_;

    die "[x] Please provide 1 or 0\n" unless $is_active =~ /^[01]$/;
    $self->{_debug} = $is_active;

    return;

}

sub active_no_greeting {

    my ( $self, $is_active ) = @_;

    die "[x] Please provide 1 or 0\n" unless $is_active =~ /^[01]$/;
    $self->{_nogreeting} = $is_active;

    return;

}

sub notify_for_bugs {

    my ( $self, $bugs_string ) = @_;

    die "[x] bugs string is undefined or invalid\n"
      unless defined $bugs_string && $self->_bugs_string_is_valid($bugs_string);

    $self->_notify_greeting unless $self->{_nogreeting};

    Lucia::Debugger::info("The following IDs will be used: $bugs_string")
        if $self->{_debug};

    my @bugs;
    my $bcp = $self->{_bcp};
    $bcp->use_model('bug');
    
    while ( @bugs = @{ $bcp->get_bugs_by_ids($bugs_string) } ) {
        foreach my $bug (@bugs) {
            # Save the bug if it doesn't exist
            if ( ! $self->_bug_exists($bug->get_id) ) {
                $self->_save_bug($bug);

                Lucia::Debugger::success(
                    sprintf('The bug %s has been saved in the box with status %s',
                    $bug->get_id, $bug->get_status)
                ) if $self->{_debug};

                next;
            }

            # Skip processing if bug status and tester platform remain the same
            if ( $self->_bug_has_same_status($bug->get_id, $bug->get_status) &&
                 $self->_tester_is_the_same($bug->get_id, $bug->get_rep_platform) ) {

                Lucia::Debugger::info(
                    sprintf(
                        'Skipping iteration because bug %s or tester status has not changed',
                        $bug->get_id
                    )
                ) if $self->{_debug};

                next;
             }

            # Alert about the bug change and save the bug
            $self->_alert_change($bug);
            $self->_save_bug($bug);

            Lucia::Debugger::success(
                sprintf('The bug %s has been updated in the box with status %s',
                $bug->get_id, $bug->get_status)
            ) if $self->{_debug};
        }

        Lucia::Debugger::info(
            sprintf(
                'Sleeping for %d seconds before continuing to check for bugs',
                $self->{_time}
            )
        ) if $self->{_debug};

        $self->_wait_time_for_notification();
    }

    return;

}

sub notify_for_user {

    my ( $self, $username ) = @_;

    $self->_notify_greeting unless $self->{_nogreeting};

    my @bugs;

    my $bcp = $self->{_bcp};

    $bcp->use_model('user');
    my $user = $bcp->get_user_by_username($username);
    die "[x] User does not exist\n" unless $user;

    Lucia::Debugger::info("Getting bugs from user $username")
        if $self->{_debug};

    $bcp->use_model('bug');

    while ( 1 ) {
        $self->_wait_time_for_notification();

        @bugs = @{ $bcp->get_bugs_by_userid($user->get_id) };
        if ( !@bugs ) {
            Lucia::Debugger::warning(
                sprintf('There are no bugs available for %s', $username)
            ) if $self->{_debug};
            next;
        };

        foreach my $bug ( @bugs ) {
            # Save the bug if it doesn't exist
            if ( ! $self->_bug_exists($bug->get_id) ) {
                $self->_save_bug($bug);

                Lucia::Debugger::success(
                    sprintf('The bug %s has been saved in the box with status %s',
                    $bug->get_id, $bug->get_status)
                ) if $self->{_debug};

                next;
            }

            # Skip processing if bug status and tester platform remain the same
            if ( $self->_bug_has_same_status($bug->get_id, $bug->get_status) &&
                 $self->_tester_is_the_same($bug->get_id, $bug->get_rep_platform) ) {

                Lucia::Debugger::warning(
                    sprintf(
                        'Skipping iteration because bug %s or tester status has not changed',
                        $bug->get_id
                    )
                ) if $self->{_debug};

                next;
             }

            # Alert about the bug change and update the bug
            $self->_alert_change($bug);
            $self->_save_bug($bug);

            Lucia::Debugger::success(
                sprintf('The bug %s has been updated in the box with status %s',
                $bug->get_id, $bug->get_status)
            ) if $self->{_debug};
        }

        Lucia::Debugger::info(
            sprintf(
                'Sleeping for %d seconds before continuing to check for bugs',
                $self->{_time}
            )
        ) if $self->{_debug};
    }

    return;

}

sub _notify_greeting {

    my $self = shift;

    my $username = $ENV{USER};
    my $header = $self->_create_message_with_dict('TEXT_GREETING_NOTIFY_HEADER', [$username]);
    my $body = $self->_create_message_with_dict('TEXT_GREETING_NOTIFY_BODY');

    $self->_send_notification(
        header => $header,
        body   => $body,
    );

    if ( $self->{_voice_engine} ) {
        my $message = $self->_create_message_with_dict('VOICE_GREETING', [$username]);
        $self->_play_voice($message);
    }

}

sub _bug_exists {

    my ( $self, $bug_id ) = @_;
    return exists $self->{_bug_box}->{$bug_id};

}

sub _save_bug {

    my ( $self, $bug ) = @_;
    $self->{_bug_box}->{ $bug->get_id } = $bug;
    store $self->{_bug_box}, BUG_BOX_NAME;
    $self->{_bug_box} = retrieve(BUG_BOX_NAME);

    return;

}

sub _bug_has_same_status {

    my ( $self, $bug_id, $current_bug_status ) = @_;

    my $old_bug = $self->{_bug_box}->{$bug_id};
    return $old_bug->get_status eq $current_bug_status;

}

sub _tester_is_the_same {

    my ( $self, $bug_id, $current_tester ) = @_;

    my $old_bug = $self->{_bug_box}->{$bug_id};
    my $old_tester = $old_bug->get_rep_platform;
    return $old_tester eq $current_tester;

}

sub simulate {

    my ( $self, $bugs_string ) = @_;

    die "[x] bugs string is undefined or invalid\n"
    unless defined $bugs_string && $self->_bugs_string_is_valid($bugs_string);

    my @bug_ids = split /,/, $bugs_string;

    foreach my $bug_id (@bug_ids) {
        $self->_wait_random_time_for_notification();
        my $bug = $self->_create_dummy_bug($bug_id);
        $self->_alert_change($bug);
    }

    return;

}

sub _alert_change {

    my ( $self, $bug ) = @_;

    my $bug_alias = $self->_create_alias_for_bug_status(
        tester     => $bug->get_rep_platform,
        resolution => $bug->get_resolution,
        status     => $bug->get_status
    );

    my $header = $self->_create_message_with_dict('TEXT_BUG_NOTIFY_HEADER', [ $bug->get_id, $bug->get_description ]);
    my $body = $self->_create_message_with_dict('TEXT_BUG_NOTIFY_BODY_1', [ $bug->get_status, $bug->get_resolution, $bug->get_rep_platform ]);
    $body .= $bug_alias ? $self->_create_message_with_dict('TEXT_BUG_NOTIFY_BODY_2', [$bug_alias])
                        : $self->_create_message_with_dict('TEXT_BUG_NOTIFY_BODY_3');
    my $icon = 'icons/notified.png';

    $self->_send_notification(
        header => $header,
        body   => $body,
        icon   => $icon,
    );

    if ( $self->{_voice_engine} ) {
        my $message = $self->_create_message_with_dict('VOICE_BUG_NOTIFY', [ $bug->get_id, $bug_alias ]);
        $self->_play_voice($message);
    }

    return;

}

sub _create_alias_for_bug_status {

    my ( $self, %args ) = @_;

    my $tester     = $args{tester};
    my $resolution = $args{resolution};
    my $status     = $args{status};

    my %status_aliases = (
        'NEW'      => $self->_create_message_with_dict('TEXT_NEW_ALIAS'),
        'REOPENED' => $self->_create_message_with_dict('TEXT_REOPENED_ALIAS'),
        'ASSIGNED' => $self->_create_message_with_dict('TEXT_ASSIGNED_ALIAS'),
        'RESOLVED' => {
            'FIXED' => {
                'Sin Asignar' => $self->_create_message_with_dict('TEXT_RESOLVED_FIXED_ALIAS_1'),
                'Asignado' => $self->_create_message_with_dict('TEXT_RESOLVED_FIXED_ALIAS_2'),
            },
        },
        'VERIFIED' => {
            'FIXED' => $self->_create_message_with_dict('TEXT_VERIFIED_FIXED_ALIAS'),
        },
        'REOPENED-MERGE' => $self->_create_message_with_dict('TEXT_REOPENED_MERGE_ALIAS'),
    );

    my $alias = $status_aliases{$status};

    if ( ref $alias eq 'HASH' ) {
        $alias = $alias->{$resolution};
        if ( ref $alias eq 'HASH' ) {
            $alias = $alias->{$tester} // $alias->{Asignado};
        }
    }

    return $alias;

}


sub _bugs_string_is_valid {

    my ( $self, $bugs_string ) = @_;
    return $bugs_string =~ m/^(?:\d+,?)+$/;

}

sub _wait_random_time_for_notification {

    my $self        = shift;
    my $random_time = int rand 10;
    $self->_wait_time_for_notification($random_time);
    return;

}

sub _wait_time_for_notification {

    my ( $self, $time ) = @_;
    sleep( $time || $self->{_time} );
    return;

}

sub _create_dummy_bug {

    my ( $self, $bug_id ) = @_;
    my $description  = $self->_create_message_with_dict('TEXT_SIMULATE_DESCRIPTION');

    require Lucia::BugChurch::Entities::Bug;

    my $bug = Lucia::BugChurch::Entities::Bug->new;
    $bug->set_id($bug_id);
    $bug->set_status('RESOLVED');
    $bug->set_description($description);
    $bug->set_rep_platform('Emily');
    $bug->set_resolution('FIXED');

    return $bug;

}

sub _create_message_with_dict {

    my ( $self, $term, $items ) = @_;

    my $lang = $self->{_lang};
    my $dict = $self->{_dict};

    my $message = $dict->get_definition($term, $lang);

    if ( $items ) {
        my @items = @{$items};
        $message = sprintf $message, @items;
    }

    return $message;

}

sub _send_notification {

    my ( $self, %args ) = @_;

    my $notification = $self->{_notify};

    $notification->set_app_name('Lucia');
    $notification->set_header($args{header});
    $notification->set_body($args{body});
    $notification->active_sound($self->{_sound});

    $notification->notify;

    return;

}

sub _play_voice {

    my ( $self, $message ) = @_;

    my $prototts = $self->{_voice_engine};
    $prototts->set_message($message);
    $prototts->set_voice($LUCIA_VOICES{ $self->{_lang} });
    $prototts->play;

    return;

}

1;
