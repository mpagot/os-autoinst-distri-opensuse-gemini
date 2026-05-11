#!/usr/bin/perl
# extract_log_section.pl — List or extract test module sections from openQA autoinst-log files.
# Run with --help for full usage information.

use strict;
use warnings;
use Getopt::Long;
use JSON::PP;
use Term::ANSIColor qw(colored);

my $verbose     = 0;
my $json_output = 0;
my $use_color   = 0;
my $help        = 0;

GetOptions(
    'verbose' => \$verbose,
    'json'    => \$json_output,
    'color'   => \$use_color,
    'help|h'  => \$help,
) or do { print_usage(); exit 1 };

if ($help) { print_usage(); exit 0 }

my $log_input   = shift @ARGV or do { print_usage(); exit 1 };
my $module_name = shift @ARGV;

my $log_file = resolve_log_file($log_input);

if (defined $module_name) {
    extract_module($log_file, $module_name);
} else {
    list_modules($log_file);
}

=head2 resolve_log_file($path)

Resolves the log file path. If C<$path> is a directory, appends
C<autoinst-log.txt>. Dies if the resolved file does not exist.

=cut

sub resolve_log_file {
    my ($input) = @_;
    my $file = (-d $input) ? "$input/autoinst-log.txt" : $input;
    $file =~ s{/+}{/}g;
    die "Error: Log file '$file' not found.\n" unless -f $file;
    warn "Using log file: $file\n" if $verbose;
    return $file;
}

=head2 list_modules($log_file)

Lists all test module names found in the log file by scanning for
C<||| starting> and C<scheduling> patterns. Output is sorted and unique.

=cut

sub list_modules {
    my ($file) = @_;
    my %modules;

    open my $fh, '<', $file or die "Cannot open '$file': $!\n";
    while (my $line = <$fh>) {
        if ($line =~ /\|\|\| starting\s+(\S+)\s+/) {
            $modules{$1} = 1;
        }
        elsif ($line =~ /scheduling\s+(\S+)\s+/) {
            $modules{$1} = 1;
        }
    }
    close $fh;

    my @sorted = sort keys %modules;

    if ($json_output) {
        print JSON::PP->new->pretty->canonical->encode({modules => \@sorted});
    } else {
        my $header = "Modules in '$file':";
        if ($use_color) {
            print colored($header, 'bold'), "\n";
            print colored('-' x length($header), 'cyan'), "\n";
        } else {
            print "$header\n";
            print '-' x length($header), "\n";
        }
        print "$_\n" for @sorted;
    }
}

=head2 extract_module($log_file, $module_name)

Extracts the log section for a specific module. Tries the C<||| starting>
pattern first, then falls back to the C<scheduling> pattern.
Writes output to C<< <module_name>.log >>.

=cut

sub extract_module {
    my ($file, $mod) = @_;
    my $output_file = "${mod}.log";

    # Try Variant 1: ||| starting
    warn "Attempting extraction with '||| starting' pattern...\n" if $verbose;
    my @lines = _extract_with_pattern($file, $mod, qr/\|\|\| starting \Q$mod\E /);

    # Fallback to Variant 2: scheduling
    if (!@lines) {
        warn "Standard pattern not found. Trying 'scheduling' pattern...\n" if $verbose;
        @lines = _extract_with_pattern($file, $mod, qr/scheduling \Q$mod\E /);
    }

    if (@lines) {
        open my $out, '>', $output_file or die "Cannot write '$output_file': $!\n";
        print $out @lines;
        close $out;

        my $count = scalar @lines;
        if ($json_output) {
            print JSON::PP->new->pretty->canonical->encode({
                module      => $mod,
                output_file => $output_file,
                lines       => $count,
            });
        } else {
            my $msg = "Successfully extracted log to $output_file ($count lines)";
            print $use_color ? colored($msg, 'green') . "\n" : "$msg\n";
        }
    } else {
        if ($json_output) {
            print JSON::PP->new->pretty->canonical->encode({
                error  => 'Pattern not found',
                module => $mod,
            });
        }
        die "Failed to extract log for module '$mod'. Pattern not found.\n";
    }
}

=head2 _extract_with_pattern($file, $module, $start_re)

Extracts lines from C<$file> starting when C<$start_re> matches and ending
when C<||| finished $module> or C<Test died: script timeout> is seen.

=cut

sub _extract_with_pattern {
    my ($file, $mod, $start_re) = @_;
    my $finish_re = qr/\|\|\| finished \Q$mod\E /;
    my @extracted;
    my $capturing = 0;

    open my $fh, '<', $file or die "Cannot open '$file': $!\n";
    while (my $line = <$fh>) {
        if (!$capturing && $line =~ $start_re) {
            $capturing = 1;
        }
        if ($capturing) {
            push @extracted, $line;
            last if $line =~ $finish_re || $line =~ /Test died: script timeout/;
        }
    }
    close $fh;
    return @extracted;
}

sub print_usage {
    print <<'USAGE';
Usage: extract_log_section.pl [OPTIONS] <log_file_or_dir> [module_name]

List or extract test module sections from openQA autoinst-log files.

Arguments:
  log_file_or_dir   Path to autoinst-log.txt or directory containing it
  module_name       Module to extract (omit to list all modules)

Options:
  --json            Output results as JSON
  --color           Enable colored output
  --verbose         Print progress messages
  --help, -h        Show this help

Examples:
  extract_log_section.pl /path/to/logs/              # List modules
  extract_log_section.pl /path/to/autoinst-log.txt   # List modules
  extract_log_section.pl /path/to/logs/ my_module    # Extract module log
  extract_log_section.pl --json /path/to/logs/       # List as JSON
USAGE
}
