#!/usr/bin/env perl
#
# pcontext.pl - Repository context dumper for LLMs
#
# Transforms source code repositories into comprehensive, LLM-friendly
# Markdown documents with structure overview, language stats, and file contents.
#
use strict;
use warnings;
use utf8;
use FindBin qw($RealBin);
use lib "$RealBin/lib";
use Getopt::Long;
use Cwd 'abs_path';
use PContext qw(analyze_repository);

binmode STDOUT, ':encoding(UTF-8)';

our $VERSION = '1.0.0';

sub print_help {
    print <<"HELP";
pcontext.pl v$VERSION - Repository Context Dumper for LLMs

Usage:
  $0 [--git_url URL] [--compress] [path]
  $0 --help

Options:
  --git_url URL   Clone a Git repository from URL and analyze it
  --compress      Output compressed mode (structure only, no file contents)
  --help          Show this help message

Environment Variables:
  REPO_DUMP_MAX_BYTES    Max file size in bytes (default: 300000)
  REPO_DUMP_MAX_LINES    Lines per chunk, 0=no chunking (default: 1200)
  REPO_DUMP_LINE_NUMBERS Add line numbers if set to 1
  REPO_DUMP_ONLY_EXT     Comma-separated extensions to include (e.g., "py,js,ts")
  REPO_DUMP_EXCLUDE      Comma-separated glob patterns to exclude

Examples:
  $0 .
  $0 /path/to/repo
  $0 --git_url https://github.com/user/repo.git
  $0 --compress .
  REPO_DUMP_ONLY_EXT="py,ts" $0 .

HELP
    exit 0;
}

sub main {
    my $git_url  = undef;
    my $help     = 0;
    my $compress = 0;

    GetOptions(
        'git_url=s' => \$git_url,
        'help'      => \$help,
        'compress'  => \$compress,
    ) or die "Usage: $0 [--git_url URL] [--compress] [path]\n";

    print_help() if $help;

    # Build parameters for analyze_repository
    my %params = ( compress => $compress, );

    if ($git_url) {
        $params{git_url} = $git_url;
        print STDERR "# Cloning $git_url...\n";
    }
    else {
        my $path = shift @ARGV // '.';
        $params{path} = abs_path($path) if -e $path;
        $params{path} //= $path;
    }

    # Apply environment variable overrides
    if ( $ENV{REPO_DUMP_MAX_BYTES} ) {
        $params{max_file_size} = $ENV{REPO_DUMP_MAX_BYTES};
    }
    if ( defined $ENV{REPO_DUMP_MAX_LINES} ) {
        $params{max_lines_per_chunk} = $ENV{REPO_DUMP_MAX_LINES};
    }
    if ( $ENV{REPO_DUMP_LINE_NUMBERS} ) {
        $params{include_line_numbers} = 1;
    }
    if ( $ENV{REPO_DUMP_ONLY_EXT} ) {
        $params{include_extensions} =
          [ split /\s*,\s*/, $ENV{REPO_DUMP_ONLY_EXT} ];
    }
    if ( $ENV{REPO_DUMP_EXCLUDE} ) {
        $params{exclude_patterns} =
          [ split /\s*,\s*/, $ENV{REPO_DUMP_EXCLUDE} ];
    }

    # Run analysis
    my $result = analyze_repository( \%params );

    if ( !$result->{success} ) {
        my $error = $result->{error}  || {};
        my $msg   = $error->{message} || 'Unknown error';
        die "Error: $msg\n";
    }

    # Output the content
    print $result->{content};

    # Print summary to stderr
    my $meta = $result->{metadata} || {};
    print STDERR "\n# Analysis complete: $meta->{total_files} files, ";
    print STDERR "$meta->{total_dirs} dirs, ~$meta->{approx_tokens} tokens\n";
}

main();

__END__

=head1 NAME

pcontext.pl - Repository context dumper for LLMs

=head1 SYNOPSIS

    pcontext.pl [--git_url URL] [--compress] [path]
    pcontext.pl --help

=head1 DESCRIPTION

Transforms source code repositories into comprehensive, LLM-friendly
Markdown documents. Generates a structured overview including:

=over 4

=item * Repository overview (files, directories, token estimates)

=item * Language statistics and breakdown

=item * Directory tree structure

=item * Annotated file contents in code fences

=back

=head1 OPTIONS

=over 4

=item B<--git_url> I<URL>

Clone the specified Git repository and analyze it. Uses shallow clone.

=item B<--compress>

Output structure only without file contents. Produces ~50x smaller output.

=item B<--help>

Print help message and exit.

=back

=head1 ENVIRONMENT VARIABLES

=over 4

=item B<REPO_DUMP_MAX_BYTES>

Maximum file size in bytes to include content (default: 300000).

=item B<REPO_DUMP_MAX_LINES>

Maximum lines per chunk. Set to 0 to disable chunking (default: 1200).

=item B<REPO_DUMP_LINE_NUMBERS>

If set to 1, prefix each line with its line number.

=item B<REPO_DUMP_ONLY_EXT>

Comma-separated list of file extensions to include (e.g., "py,js,ts").

=item B<REPO_DUMP_EXCLUDE>

Comma-separated glob patterns to exclude (e.g., "docs/*,*.min.js").

=back

=head1 EXAMPLES

    # Analyze current directory
    pcontext.pl .

    # Analyze a remote repository
    pcontext.pl --git_url https://github.com/user/repo.git

    # Quick overview without file contents
    pcontext.pl --compress /path/to/repo

    # Filter by extension
    REPO_DUMP_ONLY_EXT="py,ts" pcontext.pl .

=cut
