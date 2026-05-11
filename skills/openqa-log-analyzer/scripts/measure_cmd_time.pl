#!/usr/bin/perl
# measure_cmd_time.pl — Measure command execution time from openQA autoinst-log files.
# Parses testapi calls and correlates them with serial output durations.
# Run with --help for full usage information.

use strict;
use warnings;
use Getopt::Long;
use JSON::PP;
use Term::ANSIColor qw(colored);

my $verbose     = 0;
my $json_output = 0;
my $use_color   = 0;
my $duration_expr;
my $help        = 0;

GetOptions(
    'verbose'    => \$verbose,
    'json'       => \$json_output,
    'color'      => \$use_color,
    'duration=s' => \$duration_expr,
    'help|h'     => \$help,
) or do { print_usage(); exit 1 };

if ($help) { print_usage(); exit 0 }

my $log_file = shift @ARGV or do { print_usage(); exit 1 };
my $search   = shift @ARGV;

die "Error: Log file '$log_file' not found.\n" unless -f $log_file;

my $results = parse_log($log_file);

if (!@$results) {
    print "No commands found with measurable execution time.\n";
    exit 0;
}

# Apply duration filter
if (defined $duration_expr) {
    my $df = DurationFilter->new($duration_expr);
    $results = [grep { $df->evaluate($_->{duration}) } @$results];
}

# Apply search filter
if (defined $search) {
    my $q = lc $search;
    $results = [grep { index(lc $_->{api}, $q) >= 0 || index(lc $_->{cmd}, $q) >= 0 } @$results];
}

if (!@$results) {
    print "No results matching the filters.\n";
    exit 0;
}

# Output
if ($json_output) {
    print JSON::PP->new->pretty->canonical->encode({
        results => $results,
        count   => scalar @$results,
        filters => {
            duration => $duration_expr,
            search   => $search,
        },
    });
} else {
    my $header  = 'Duration    | Timestamp             | Test API          | Script Caller (File:Line)';
    $header    .= '                | Log Line   | RC   | Tag   | Command';
    my $divider = '-' x length($header);

    if ($use_color) {
        print colored($header, 'bold'), "\n";
        print colored($divider, 'cyan'), "\n";
    } else {
        print "$header\n$divider\n";
    }

    for my $r (@$results) {
        my $line = format_result($r);
        if ($use_color && $r->{duration} > 10) {
            print colored($line, 'yellow');
        } elsif ($use_color && $r->{rc} ne '0') {
            print colored($line, 'red');
        } else {
            print $line;
        }
        print "\n";
    }
}

# ======================================================================
# DurationFilter — evaluates boolean expressions like ">1 && <=10"
# ======================================================================
{
    package DurationFilter;

    sub new {
        my ($class, $expression) = @_;
        my $self = bless {expression => $expression}, $class;
        $self->{clauses} = $self->_parse_expression($expression);
        return $self;
    }

=head2 DurationFilter::_parse_expression($expr)

Parses a duration filter expression into a list of clauses.
Supports operators: C<< > >= < <= == != >> and connectives C<&&> C<||>.
Example: C<< ">1 && <=10" >> or C<< ">=5 || ==0" >>.

=cut

    sub _parse_expression {
        my ($self, $expr) = @_;
        my @parts = split /(\s*&&\s*|\s*\|\|\s*)/, $expr;
        my @parsed;
        for my $part (@parts) {
            $part =~ s/^\s+|\s+$//g;
            if ($part eq '&&' || $part eq '||') {
                push @parsed, $part;
            } elsif ($part =~ /^(>=|<=|>|<|==|!=|=)?\s*([\d.]+)\s*s?$/) {
                my $op = $1 // '==';
                $op = '==' if $op eq '=';
                push @parsed, {op => $op, val => $2 + 0};
            }
        }
        return \@parsed;
    }

=head2 DurationFilter::evaluate($duration)

Evaluates the filter expression against a duration value.
Returns 1 if the duration passes the filter, 0 otherwise.
Operator precedence: C<&&> binds tighter than C<||>.

=cut

    sub evaluate {
        my ($self, $duration) = @_;
        my @clauses = @{$self->{clauses}};
        return 1 unless @clauses;

        # First pass: evaluate individual conditions
        my @results;
        for my $clause (@clauses) {
            if (!ref $clause) {
                push @results, $clause;
            } else {
                my ($op, $val) = @{$clause}{qw(op val)};
                my $res;
                if    ($op eq '>')  { $res = $duration > $val }
                elsif ($op eq '>=') { $res = $duration >= $val }
                elsif ($op eq '<')  { $res = $duration < $val }
                elsif ($op eq '<=') { $res = $duration <= $val }
                elsif ($op eq '==') { $res = abs($duration - $val) < 0.0001 }
                elsif ($op eq '!=') { $res = abs($duration - $val) >= 0.0001 }
                else                { $res = 1 }
                push @results, $res ? 1 : 0;
            }
        }

        return 1 unless @results;

        # Second pass: handle && (higher precedence)
        my $i = 0;
        while ($i < scalar @results) {
            if (!ref $results[$i] && $results[$i] eq '&&') {
                my $left  = $results[$i - 1];
                my $right = $results[$i + 1];
                splice @results, $i - 1, 3, ($left && $right ? 1 : 0);
            } else {
                $i++;
            }
        }

        # Third pass: handle ||
        my $final = $results[0];
        $i = 1;
        while ($i < scalar @results) {
            if (!ref $results[$i] && $results[$i] eq '||') {
                $final = ($final || $results[$i + 1]) ? 1 : 0;
                $i += 2;
            } else {
                $i++;
            }
        }

        return $final ? 1 : 0;
    }
}

# ======================================================================
# Log parsing
# ======================================================================

=head2 clean_string($s)

Removes log-escaped characters and non-printable characters from a string.

=cut

sub clean_string {
    my ($s) = @_;
    return '' unless defined $s && length $s;
    $s =~ s/\\"/"/g;
    $s =~ s/\\\\/\\/g;
    $s =~ s/[^[:print:]]//g;
    return $s;
}

=head2 parse_log($file_path)

Parses an autoinst-log file and extracts command execution timing data.
Uses a state machine to correlate testapi calls (script_run, assert_script_run,
ssh_script_output, etc.) with their completion markers.

Returns an arrayref of result hashrefs with keys: duration, ts, api, caller,
line, rc, tag, cmd.

=cut

sub parse_log {
    my ($file_path) = @_;

    # Tag pattern: 5 non-whitespace, non-hyphen characters
    my $TAG = qr/[^\s\-]{5}/;

    # State tracking
    my %pid_to_last_api;
    my %pid_to_last_cmd;
    my %pid_to_last_caller;
    my $last_caller_global = 'unknown:0';
    my %tag_to_info;
    my @results;

    open my $fh, '<', $file_path or die "Cannot open '$file_path': $!\n";
    my $line_num = 0;

    while (my $line = <$fh>) {
        $line_num++;
        chomp $line;

        # Extract PID from any log line
        my $pid;
        if ($line =~ /\[pid:(\d+)\]/) {
            $pid = $1;
        }

        # --- State: track testapi calls ---
        if ($line =~ /<<< testapi::(\w+)\(.*\b(?:cmd|text)="((?:[^"\\]|\\.)*)"/) {
            my ($api, $cmd) = ($1, $2);
            if (defined $pid) {
                $pid_to_last_api{$pid}    = $api;
                $pid_to_last_cmd{$pid}    = $cmd;
                $pid_to_last_caller{$pid} = 'unknown:0';
            }
            next;
        }

        # --- State: track caller chain ---
        if ($line =~ /\] ([^:\s]+\.p[ml]:\d+) called/) {
            my $caller = $1;
            if (defined $pid) {
                $pid_to_last_caller{$pid} = $caller;
                $last_caller_global       = $caller;
            }
            next;
        }

        # --- Linkage: wait_serial with cmd+tag (script_run style) ---
        if ($line =~ m{<<< testapi::wait_serial\(.*regexp="((?:[^"\\]|\\.)*); echo ($TAG)-[^"]+"}s) {
            my ($cmd, $tag) = ($1, $2);
            $tag_to_info{$tag} = {
                cmd    => clean_string($cmd),
                api    => (defined $pid ? ($pid_to_last_api{$pid} // 'unknown') : 'unknown'),
                caller => clean_string(defined $pid ? ($pid_to_last_caller{$pid} // 'unknown:0') : 'unknown:0'),
            };
            next;
        }

        # --- Linkage: SSH command in serial_screen::type_string ---
        if ($line =~ /serial_screen::type_string/ && $line =~ /ssh/) {
            my ($ssh_cmd, $tag);
            if ($line =~ /--\s+\\\$'(?:sudo\s+)?([^']+)'/) {
                $ssh_cmd = $1;
            }
            if ($line =~ /EOT_($TAG)/) {
                $tag = $1;
            }
            if (defined $ssh_cmd && defined $tag) {
                $tag_to_info{$tag} = {
                    cmd    => clean_string($ssh_cmd),
                    api    => 'ssh_script_output',
                    caller => clean_string($last_caller_global),
                };
                next;
            }
            # Fall through if not both matched
        }

        # --- Linkage: tag pattern in wait_serial regexp (script_output style) ---
        if ($line =~ m{regexp=qr/($TAG)-\\d+-/}) {
            my $tag = $1;
            if (!exists $tag_to_info{$tag} && defined $pid && exists $pid_to_last_cmd{$pid}) {
                $tag_to_info{$tag} = {
                    cmd    => clean_string($pid_to_last_cmd{$pid}),
                    api    => $pid_to_last_api{$pid} // 'unknown',
                    caller => clean_string($pid_to_last_caller{$pid} // 'unknown:0'),
                };
            }
            next;
        }

        # --- Duration: only process [info] lines with "Matched output" ---
        next unless $line =~ /\[info\]/ && $line =~ /Matched output from SUT/;

        # Extract and shorten timestamp
        my $ts = 'unknown';
        if ($line =~ /^\[([^\]]+)\]/) {
            $ts = $1;
        }
        my $short_ts = $ts;
        if ($ts =~ /^([^.]+)\.(..)/) {
            $short_ts = "$1.$2";
        }

        # --- Duration: SCRIPT_FINISHED (script_output / ssh_script_output) ---
        if ($line =~ /Matched output from SUT in .* & ([\d.]+) seconds: SCRIPT_FINISHED($TAG)-(\d+)-/) {
            my ($duration, $tag, $rc) = ($1 + 0, $2, $3);
            my $info = $tag_to_info{$tag} // {cmd => 'Unknown command', api => 'unknown', caller => 'unknown:0'};

            # Remove the last setup-echo for same tag (tags are reused)
            for my $idx (reverse 0 .. $#results) {
                if ($results[$idx]{tag} eq $tag && $results[$idx]{duration} < 0.01) {
                    splice @results, $idx, 1;
                    last;
                }
            }

            push @results, {
                duration => $duration,
                ts       => $short_ts,
                api      => $info->{api},
                caller   => $info->{caller},
                line     => $line_num,
                rc       => $rc,
                tag      => $tag,
                cmd      => $info->{cmd},
            };
            next;
        }

        # --- Duration: plain <tag>-<rc>- (script_run style) ---
        if ($line =~ /Matched output from SUT in .* & ([\d.]+) seconds: ($TAG)-(\d+)-/) {
            my ($duration, $tag, $rc) = ($1 + 0, $2, $3);
            my $info = $tag_to_info{$tag} // {cmd => 'Unknown command', api => 'unknown', caller => 'unknown:0'};

            push @results, {
                duration => $duration,
                ts       => $short_ts,
                api      => $info->{api},
                caller   => $info->{caller},
                line     => $line_num,
                rc       => $rc,
                tag      => $tag,
                cmd      => $info->{cmd},
            };
        }
    }
    close $fh;

    return \@results;
}

=head2 format_result($result_hashref)

Formats a single result hashref into a fixed-width table row string.

=cut

sub format_result {
    my ($r) = @_;
    return sprintf("%10.4fs | %-21s | %-17s | %-40s | %-10d | %-4s | %s | %s",
        $r->{duration}, $r->{ts}, $r->{api}, $r->{caller},
        $r->{line}, $r->{rc}, $r->{tag}, $r->{cmd});
}

sub print_usage {
    print <<'USAGE';
Usage: measure_cmd_time.pl [OPTIONS] <log_file> [search_term]

Measure command execution time from openQA autoinst-log files. Parses
testapi calls (script_run, assert_script_run, ssh_script_output, etc.)
and correlates them with serial output completion markers.

Arguments:
  log_file       Path to autoinst-log.txt
  search_term    Optional string to filter commands or API names

Options:
  --duration EXPR   Filter by duration expression
                    Examples: ">1s", ">=2 && <=10", ">5 || ==0"
                    Operators: > >= < <= == !=
                    Connectives: && (AND, higher precedence), || (OR)
  --json            Output results as JSON
  --color           Enable colored output (slow cmds yellow, non-zero RC red)
  --verbose         Print progress messages
  --help, -h        Show this help

Output columns:
  Duration    Execution time in seconds
  Timestamp   Log timestamp (shortened to centiseconds)
  Test API    testapi function name (script_run, ssh_script_output, etc.)
  Caller      Source file and line number that invoked the command
  Log Line    Line number in the log file
  RC          Return code of the command
  Tag         5-character tag linking start and finish
  Command     The actual shell command executed

Examples:
  measure_cmd_time.pl autoinst-log.txt
  measure_cmd_time.pl --duration ">5" autoinst-log.txt
  measure_cmd_time.pl --duration ">1 && <=30" autoinst-log.txt zypper
  measure_cmd_time.pl --json autoinst-log.txt
USAGE
}
