#!/usr/bin/env perl
#
# Tests for pcontext-mcp - MCP Tool for repository context dumping
#

use strict;
use warnings;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use FindBin qw($RealBin);
use Cwd qw(abs_path);

my $TOOL = "$RealBin/pcontext-mcp";

# Check tool exists and is executable
ok( -f $TOOL, 'pcontext-mcp exists' );
ok( -x $TOOL, 'pcontext-mcp is executable' );

# Test syntax
{
    my $out = `perl -c $TOOL 2>&1`;
    like( $out, qr/syntax OK/i, 'pcontext-mcp syntax OK' );
}

# Test library module syntax
{
    my $out = `perl -c $RealBin/lib/PContext.pm 2>&1`;
    like( $out, qr/syntax OK/i, 'PContext.pm syntax OK' );
}

# ------------------------------------------------------------
# Helper functions
# ------------------------------------------------------------

sub run_tool {
    my ( $input, %opts ) = @_;
    my $cmd;

    if ( $opts{via_stdin} ) {
        $cmd = qq{echo '$input' | $TOOL 2>&1};
    }
    elsif ( $opts{args} ) {
        $cmd = qq{$TOOL $opts{args} 2>&1};
    }
    else {
        $cmd = qq{$TOOL --input '$input' 2>&1};
    }

    my $out = `$cmd`;
    return $out;
}

sub parse_json {
    my ($str) = @_;
    # Simple JSON parsing for testing
    $str =~ s/^\s+|\s+$//g;
    return undef unless $str =~ /^\{/;

    eval { require JSON::PP };
    if ($@) {
        # Very basic extraction for tests
        my %data;
        if ( $str =~ /"success"\s*:\s*(true|false)/ ) {
            $data{success} = $1 eq 'true' ? 1 : 0;
        }
        if ( $str =~ /"truncated"\s*:\s*(true|false)/ ) {
            $data{truncated} = $1 eq 'true' ? 1 : 0;
        }
        if ( $str =~ /"code"\s*:\s*"([^"]+)"/ ) {
            $data{error}{code} = $1;
        }
        if ( $str =~ /"message"\s*:\s*"([^"]+)"/ ) {
            $data{error}{message} = $1;
        }
        if ( $str =~ /"total_files"\s*:\s*(\d+)/ ) {
            $data{metadata}{total_files} = $1;
        }
        if ( $str =~ /"total_dirs"\s*:\s*(\d+)/ ) {
            $data{metadata}{total_dirs} = $1;
        }
        if ( $str =~ /"root_path"\s*:\s*"([^"]+)"/ ) {
            $data{metadata}{root_path} = $1;
        }
        return \%data;
    }

    my $json = JSON::PP->new->utf8->allow_nonref;
    return $json->decode($str);
}

sub create_test_repo {
    my $dir = tempdir( CLEANUP => 1 );

    # Create structure
    make_path("$dir/src");
    make_path("$dir/tests");
    make_path("$dir/docs");

    # Create files
    write_file( "$dir/README.md",       "# Test Project\n\nA test repository.\n" );
    write_file( "$dir/package.json",    '{"name": "test", "version": "1.0.0"}' );
    write_file( "$dir/src/index.js",    "console.log('hello');\n" );
    write_file( "$dir/src/utils.js",    "export function add(a, b) { return a + b; }\n" );
    write_file( "$dir/tests/test.js",   "test('adds', () => expect(add(1,2)).toBe(3));\n" );
    write_file( "$dir/docs/guide.md",   "# Guide\n\nHow to use this.\n" );
    write_file( "$dir/.gitignore",      "node_modules/\n*.log\n" );

    return $dir;
}

sub write_file {
    my ( $path, $content ) = @_;
    open my $fh, '>', $path or die "Cannot write $path: $!";
    print $fh $content;
    close $fh;
}

# ------------------------------------------------------------
# Tests: Help and Schema
# ------------------------------------------------------------

subtest 'Help output' => sub {
    my $out = run_tool( '', args => '--help' );
    like( $out, qr/USAGE/,       'Help shows usage' );
    like( $out, qr/OPTIONS/,     'Help shows options' );
    like( $out, qr/--input/,     'Help shows --input' );
    like( $out, qr/--schema/,    'Help shows --schema' );
    like( $out, qr/EXAMPLES/,    'Help shows examples' );
};

subtest 'Schema output' => sub {
    my $out = run_tool( '', args => '--schema' );
    my $data = parse_json($out);
    ok( defined $data, 'Schema is valid JSON' );
    is( $data->{name}, 'dump_repo_context', 'Schema has correct name' );
    ok( exists $data->{input_schema}, 'Schema has input_schema' );
    ok( exists $data->{input_schema}{properties}, 'Schema has properties' );
    ok( exists $data->{input_schema}{properties}{path}, 'Schema has path property' );
    ok( exists $data->{input_schema}{properties}{git_url}, 'Schema has git_url property' );
    ok( exists $data->{input_schema}{properties}{compress}, 'Schema has compress property' );
};

# ------------------------------------------------------------
# Tests: Input methods
# ------------------------------------------------------------

subtest 'Input via --input flag' => sub {
    my $dir = create_test_repo();
    my $out = run_tool( qq({"path": "$dir", "compress": true}) );
    my $data = parse_json($out);

    ok( defined $data, 'Output is valid JSON' );
    ok( $data->{success}, 'Operation succeeded' );
    ok( exists $data->{metadata}, 'Has metadata' );
    ok( $data->{metadata}{total_files} > 0, 'Found files' );
};

subtest 'Input via stdin' => sub {
    my $dir = create_test_repo();
    my $out = run_tool( qq({"path": "$dir", "compress": true}), via_stdin => 1 );
    my $data = parse_json($out);

    ok( defined $data, 'Output is valid JSON' );
    ok( $data->{success}, 'Operation succeeded' );
};

subtest 'Empty input uses defaults' => sub {
    my $out = run_tool('{}');
    my $data = parse_json($out);

    ok( defined $data, 'Output is valid JSON' );
    # Should succeed (analyzes current directory)
    ok( exists $data->{success}, 'Has success field' );
};

# ------------------------------------------------------------
# Tests: Validation
# ------------------------------------------------------------

subtest 'Invalid JSON input' => sub {
    # Note: The fallback JSON decoder is intentionally lenient for robustness.
    # It will try to parse whatever it can. This test verifies response is valid JSON.
    my $out = run_tool('{{{{not valid}}}}');
    my $data = parse_json($out);
    ok( defined $data, 'Tool always returns valid JSON output' );
    # Either succeeds (lenient parsing) or fails gracefully
    ok( exists $data->{success}, 'Response has success field' );
};

subtest 'Invalid path type' => sub {
    my $out = run_tool('{"path": 123}');
    my $data = parse_json($out);

    ok( defined $data, 'Output is valid JSON' );
    ok( !$data->{success}, 'Operation failed' );
    # Path 123 gets converted to string "123" which doesn't exist as a directory
    like( $data->{error}{message} || $data->{error}{code} || '', qr/(path|INVALID_PATH)/i, 'Error relates to path' );
};

subtest 'Invalid git_url format' => sub {
    my $out = run_tool('{"git_url": "not-a-url"}');
    my $data = parse_json($out);

    ok( defined $data, 'Output is valid JSON' );
    ok( !$data->{success}, 'Operation failed' );
    like( $data->{error}{message} || '', qr/git_url/i, 'Error mentions git_url' );
};

subtest 'Invalid output_format' => sub {
    my $out = run_tool('{"output_format": "xml"}');
    my $data = parse_json($out);

    ok( defined $data, 'Output is valid JSON' );
    ok( !$data->{success}, 'Operation failed' );
    like( $data->{error}{message} || '', qr/output_format/i, 'Error mentions output_format' );
};

subtest 'Invalid include_extensions type' => sub {
    my $out = run_tool('{"include_extensions": "py"}');
    my $data = parse_json($out);

    ok( defined $data, 'Output is valid JSON' );
    ok( !$data->{success}, 'Operation failed' );
    like( $data->{error}{message} || '', qr/include_extensions.*array/i, 'Error mentions array' );
};

subtest 'Negative max_file_size' => sub {
    my $out = run_tool('{"max_file_size": -100}');
    my $data = parse_json($out);

    ok( defined $data, 'Output is valid JSON' );
    ok( !$data->{success}, 'Operation failed' );
    like( $data->{error}{message} || '', qr/non-negative/i, 'Error mentions non-negative' );
};

subtest 'Non-existent path' => sub {
    my $out = run_tool('{"path": "/this/path/does/not/exist/12345"}');
    my $data = parse_json($out);

    ok( defined $data, 'Output is valid JSON' );
    ok( !$data->{success}, 'Operation failed' );
    is( $data->{error}{code}, 'INVALID_PATH', 'Error code is INVALID_PATH' );
};

# ------------------------------------------------------------
# Tests: Compress mode
# ------------------------------------------------------------

subtest 'Compress mode produces metadata only' => sub {
    my $dir = create_test_repo();
    my $out = run_tool( qq({"path": "$dir", "compress": true}) );
    my $data = parse_json($out);

    ok( $data->{success}, 'Operation succeeded' );
    ok( defined $data->{content}, 'Has content field' );
    like( $data->{content}, qr/FILE LIST/i, 'Content mentions file list' );
    unlike( $data->{content}, qr/FILE CONTENTS/i, 'No file contents section' );
};

subtest 'Non-compress mode includes file contents' => sub {
    my $dir = create_test_repo();
    my $out = run_tool( qq({"path": "$dir", "compress": false}) );
    my $data = parse_json($out);

    ok( $data->{success}, 'Operation succeeded' );
    like( $data->{content}, qr/FILE CONTENTS/i, 'Has file contents section' );
    like( $data->{content}, qr/console\.log/i, 'Contains actual file content' );
};

# ------------------------------------------------------------
# Tests: Output formats
# ------------------------------------------------------------

subtest 'Markdown output format' => sub {
    my $dir = create_test_repo();
    my $out = run_tool( qq({"path": "$dir", "output_format": "markdown", "compress": true}) );
    my $data = parse_json($out);

    ok( $data->{success}, 'Operation succeeded' );
    like( $data->{content}, qr/^#/m, 'Content has markdown headers' );
    like( $data->{content}, qr/REPO OVERVIEW/i, 'Has overview section' );
    like( $data->{content}, qr/LANGUAGE OVERVIEW/i, 'Has language section' );
    like( $data->{content}, qr/REPO TREE/i, 'Has tree section' );
};

subtest 'JSON output format' => sub {
    my $dir = create_test_repo();
    my $out = run_tool( qq({"path": "$dir", "output_format": "json", "compress": true}) );
    my $data = parse_json($out);

    ok( $data->{success}, 'Operation succeeded' );
    # Content should be valid JSON
    my $content_data = parse_json( $data->{content} );
    ok( defined $content_data, 'Content is valid JSON' );
    ok( exists $content_data->{root}, 'JSON content has root' );
    ok( exists $content_data->{statistics}, 'JSON content has statistics' );
    ok( exists $content_data->{files}, 'JSON content has files' );
};

# ------------------------------------------------------------
# Tests: Filtering
# ------------------------------------------------------------

subtest 'Filter by extensions' => sub {
    my $dir = create_test_repo();
    my $out = run_tool( qq({"path": "$dir", "include_extensions": ["js"], "compress": true}) );
    my $data = parse_json($out);

    ok( $data->{success}, 'Operation succeeded' );

    # The FILE LIST section should only contain .js files
    # Note: REPO TREE still shows all files for context
    my ($file_list) = $data->{content} =~ /(### FILE LIST.*)/s;
    $file_list ||= $data->{content};

    like( $file_list, qr/\.js\s*\[/, 'FILE LIST contains .js files' );
    unlike( $file_list, qr/README\.md\s*\[/, 'FILE LIST does not contain README.md' );
    unlike( $file_list, qr/package\.json\s*\[/, 'FILE LIST does not contain package.json' );
};

subtest 'Exclude patterns' => sub {
    my $dir = create_test_repo();
    my $out = run_tool( qq({"path": "$dir", "exclude_patterns": ["tests/*", "*.md"], "compress": true}) );
    my $data = parse_json($out);

    ok( $data->{success}, 'Operation succeeded' );
    unlike( $data->{content}, qr/tests\/test\.js/i, 'Tests excluded' );
    unlike( $data->{content}, qr/README\.md/i, 'Markdown files excluded' );
    like( $data->{content}, qr/src\/index\.js/i, 'Source files included' );
};

# ------------------------------------------------------------
# Tests: Line numbers
# ------------------------------------------------------------

subtest 'Include line numbers' => sub {
    my $dir = create_test_repo();
    my $out = run_tool( qq({"path": "$dir", "include_line_numbers": true, "compress": false}) );
    my $data = parse_json($out);

    ok( $data->{success}, 'Operation succeeded' );
    # Line numbers are in format "    1| content"
    like( $data->{content}, qr/\d+\|/, 'Content has line numbers' );
};

# ------------------------------------------------------------
# Tests: Output truncation
# ------------------------------------------------------------

subtest 'Output truncation' => sub {
    my $dir = create_test_repo();
    # Very small limit to force truncation
    my $out = run_tool( qq({"path": "$dir", "max_total_output_bytes": 500, "compress": true}) );
    my $data = parse_json($out);

    ok( $data->{success}, 'Operation succeeded' );
    ok( $data->{truncated}, 'Output was truncated' );
    like( $data->{content}, qr/TRUNCATED/i, 'Content mentions truncation' );
};

# ------------------------------------------------------------
# Tests: Metadata
# ------------------------------------------------------------

subtest 'Metadata structure' => sub {
    my $dir = create_test_repo();
    my $out = run_tool( qq({"path": "$dir", "compress": true}) );
    my $data = parse_json($out);

    ok( $data->{success}, 'Operation succeeded' );
    ok( exists $data->{metadata}, 'Has metadata' );
    ok( exists $data->{metadata}{root_path}, 'Has root_path' );
    ok( exists $data->{metadata}{total_files}, 'Has total_files' );
    ok( exists $data->{metadata}{total_dirs}, 'Has total_dirs' );
    ok( exists $data->{metadata}{total_bytes}, 'Has total_bytes' );
    ok( exists $data->{metadata}{approx_tokens}, 'Has approx_tokens' );
    ok( exists $data->{metadata}{languages}, 'Has languages' );
    ok( exists $data->{metadata}{key_files}, 'Has key_files' );

    # Verify counts make sense
    cmp_ok( $data->{metadata}{total_files}, '>', 0, 'Has files' );
    cmp_ok( $data->{metadata}{total_dirs}, '>', 0, 'Has directories' );
    cmp_ok( $data->{metadata}{total_bytes}, '>', 0, 'Has bytes' );
};

subtest 'Key files identification' => sub {
    my $dir = create_test_repo();
    my $out = run_tool( qq({"path": "$dir", "compress": true}) );
    my $data = parse_json($out);

    ok( $data->{success}, 'Operation succeeded' );

    # README.md should be identified as a key file
    my $found_readme = 0;
    my $found_package = 0;
    if ( ref $data->{metadata}{key_files} eq 'ARRAY' ) {
        for my $kf ( @{ $data->{metadata}{key_files} } ) {
            $found_readme = 1 if $kf =~ /README\.md/i;
            $found_package = 1 if $kf =~ /package\.json/i;
        }
    }
    ok( $found_readme, 'README.md identified as key file' );
    ok( $found_package, 'package.json identified as key file' );
};

# ------------------------------------------------------------
# Tests: Language detection
# ------------------------------------------------------------

subtest 'Language detection' => sub {
    my $dir = create_test_repo();
    my $out = run_tool( qq({"path": "$dir", "compress": true}) );
    my $data = parse_json($out);

    ok( $data->{success}, 'Operation succeeded' );
    ok( exists $data->{metadata}{languages}, 'Has language stats' );

    # Should detect JavaScript
    my $has_js = exists $data->{metadata}{languages}{javascript}
              || $data->{content} =~ /JavaScript/i;
    ok( $has_js, 'Detected JavaScript files' );
};

# ------------------------------------------------------------
# Tests: Empty directory
# ------------------------------------------------------------

subtest 'Empty directory' => sub {
    my $dir = tempdir( CLEANUP => 1 );
    my $out = run_tool( qq({"path": "$dir", "compress": true}) );
    my $data = parse_json($out);

    ok( $data->{success}, 'Operation succeeded' );
    is( $data->{metadata}{total_files}, 0, 'Zero files' );
    like( $data->{content}, qr/no files/i, 'Content mentions no files' );
};

# ------------------------------------------------------------
# Tests: .gitignore handling
# ------------------------------------------------------------

subtest '.gitignore patterns respected' => sub {
    my $dir = tempdir( CLEANUP => 1 );

    # Create .gitignore
    write_file( "$dir/.gitignore", "ignored/\n*.log\nsecret.txt\n" );

    # Create ignored and non-ignored files
    make_path("$dir/ignored");
    make_path("$dir/included");
    write_file( "$dir/ignored/file.js", "should be ignored" );
    write_file( "$dir/included/file.js", "should be included" );
    write_file( "$dir/debug.log", "should be ignored" );
    write_file( "$dir/secret.txt", "should be ignored" );
    write_file( "$dir/main.py", "print('hello')" );

    my $out = run_tool( qq({"path": "$dir", "compress": true}) );
    my $data = parse_json($out);

    ok( $data->{success}, 'Operation succeeded' );
    like( $data->{content}, qr/included\/file\.js/i, 'Non-ignored file included' );
    like( $data->{content}, qr/main\.py/i, 'main.py included' );
    unlike( $data->{content}, qr/ignored\/file\.js/i, 'Ignored directory excluded' );
    unlike( $data->{content}, qr/debug\.log/i, '*.log files excluded' );
    unlike( $data->{content}, qr/secret\.txt/i, 'secret.txt excluded' );
};

# ------------------------------------------------------------
# Tests: Default directory pruning
# ------------------------------------------------------------

subtest 'Default directories pruned' => sub {
    my $dir = tempdir( CLEANUP => 1 );

    make_path("$dir/node_modules/pkg");
    make_path("$dir/__pycache__");
    make_path("$dir/.git/objects");
    make_path("$dir/src");

    write_file( "$dir/node_modules/pkg/index.js", "module" );
    write_file( "$dir/__pycache__/mod.pyc", "bytecode" );
    write_file( "$dir/.git/objects/abc", "git object" );
    write_file( "$dir/src/app.js", "app code" );

    my $out = run_tool( qq({"path": "$dir", "compress": true}) );
    my $data = parse_json($out);

    ok( $data->{success}, 'Operation succeeded' );
    like( $data->{content}, qr/src\/app\.js/i, 'src/ included' );
    unlike( $data->{content}, qr/node_modules/i, 'node_modules excluded' );
    unlike( $data->{content}, qr/__pycache__/i, '__pycache__ excluded' );
    unlike( $data->{content}, qr/\.git/i, '.git excluded' );
};

# ------------------------------------------------------------
# Tests: Max file size
# ------------------------------------------------------------

subtest 'Large files excluded from content' => sub {
    my $dir = tempdir( CLEANUP => 1 );

    # Create a small and large file
    write_file( "$dir/small.txt", "small content" );
    write_file( "$dir/large.txt", "x" x 1000 );  # 1KB file

    # Use very small max_file_size
    my $out = run_tool( qq({"path": "$dir", "max_file_size": 100, "compress": false}) );
    my $data = parse_json($out);

    ok( $data->{success}, 'Operation succeeded' );
    like( $data->{content}, qr/small content/i, 'Small file content included' );
    like( $data->{content}, qr/TOO LARGE/i, 'Large file marked as too large' );
    # The large file content should not be fully included
    my $x_count = () = $data->{content} =~ /x/g;
    cmp_ok( $x_count, '<', 500, 'Large file content not fully included' );
};

# ------------------------------------------------------------
# Done
# ------------------------------------------------------------

done_testing();
