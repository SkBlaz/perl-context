#!/usr/bin/env perl
#
# Tests for pcontext-mcp-standalone - Standalone CLI mode
#

use strict;
use warnings;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use FindBin qw($RealBin);
use Cwd qw(abs_path getcwd);

my $TOOL = "$RealBin/pcontext-mcp-standalone";

# Check tool exists and is executable
ok( -f $TOOL, 'pcontext-mcp-standalone exists' );
ok( -x $TOOL, 'pcontext-mcp-standalone is executable' );

# Test syntax
{
    my $out = `perl -c $TOOL 2>&1`;
    like( $out, qr/syntax OK/i, 'pcontext-mcp-standalone syntax OK' );
}

# ------------------------------------------------------------
# Helper functions
# ------------------------------------------------------------

sub create_test_repo {
    my $dir = tempdir( CLEANUP => 1 );

    # Create structure
    make_path("$dir/src");
    make_path("$dir/tests");

    # Create files
    open my $fh, '>', "$dir/README.md";
    print $fh "# Test Project\n\nThis is a test.\n";
    close $fh;

    open $fh, '>', "$dir/src/main.py";
    print $fh "#!/usr/bin/env python3\n\ndef main():\n    print('Hello')\n\nif __name__ == '__main__':\n    main()\n";
    close $fh;

    open $fh, '>', "$dir/tests/test_main.py";
    print $fh "def test_main():\n    assert True\n";
    close $fh;

    open $fh, '>', "$dir/package.json";
    print $fh '{"name": "test", "version": "1.0.0"}';
    close $fh;

    return $dir;
}

# ------------------------------------------------------------
# Standalone mode tests
# ------------------------------------------------------------

subtest 'Help output' => sub {
    my $out = `$TOOL --help 2>&1`;
    like( $out, qr/STANDALONE MODE/i, 'Help shows standalone mode' );
    like( $out, qr/MCP MODE/i, 'Help shows MCP mode' );
    like( $out, qr/--compress/i, 'Help shows --compress option' );
    like( $out, qr/--git_url/i, 'Help shows --git_url option' );
    like( $out, qr/EXAMPLES/i, 'Help shows examples' );
};

subtest 'Standalone mode with no arguments (current directory)' => sub {
    my $dir = create_test_repo();
    my $cwd = getcwd();
    chdir($dir);
    
    my $out = `$TOOL 2>&1`;
    my $exit = $? >> 8;
    
    chdir($cwd);
    
    is( $exit, 0, 'Exit code is 0' );
    like( $out, qr/REPO OVERVIEW/i, 'Output contains REPO OVERVIEW' );
    like( $out, qr/LANGUAGE OVERVIEW/i, 'Output contains LANGUAGE OVERVIEW' );
    like( $out, qr/REPO TREE/i, 'Output contains REPO TREE' );
    like( $out, qr/FILE CONTENTS/i, 'Output contains FILE CONTENTS' );
    like( $out, qr/README\.md/i, 'Output includes README.md' );
    like( $out, qr/main\.py/i, 'Output includes main.py' );
    like( $out, qr/Analysis complete/i, 'Output shows completion message' );
};

subtest 'Standalone mode with path argument' => sub {
    my $dir = create_test_repo();
    
    my $out = `$TOOL $dir 2>&1`;
    my $exit = $? >> 8;
    
    is( $exit, 0, 'Exit code is 0' );
    like( $out, qr/REPO OVERVIEW/i, 'Output contains REPO OVERVIEW' );
    like( $out, qr/Root: \Q$dir\E/i, 'Output shows correct root path' );
    like( $out, qr/README\.md/i, 'Output includes README.md' );
    like( $out, qr/main\.py/i, 'Output includes main.py' );
    like( $out, qr/Analyzing/i, 'Output shows analyzing message' );
};

subtest 'Standalone mode with compress flag' => sub {
    my $dir = create_test_repo();
    
    my $out = `$TOOL --compress $dir 2>&1`;
    my $exit = $? >> 8;
    
    is( $exit, 0, 'Exit code is 0' );
    like( $out, qr/REPO OVERVIEW/i, 'Compressed output has overview' );
    like( $out, qr/FILE LIST/i, 'Compressed output has file list' );
    unlike( $out, qr/FILE CONTENTS/i, 'Compressed output excludes file contents' );
    unlike( $out, qr/def main\(\):/i, 'Compressed output excludes actual code' );
    like( $out, qr/README\.md/i, 'File list includes README.md' );
};

subtest 'Standalone mode markdown output format' => sub {
    my $dir = create_test_repo();
    
    my $out = `$TOOL $dir 2>&1`;
    
    # Check markdown format
    like( $out, qr/^# Repository Context Dump/m, 'Has main header' );
    like( $out, qr/^### REPO OVERVIEW/m, 'Has section headers' );
    like( $out, qr/^### LANGUAGE OVERVIEW/m, 'Has language section' );
    like( $out, qr/^### REPO TREE/m, 'Has tree section' );
    like( $out, qr/```python:src\/main\.py/m, 'Has code fences with language' );
    like( $out, qr/=== FILE START:/m, 'Has file markers' );
    like( $out, qr/=== FILE END:/m, 'Has file end markers' );
};

subtest 'Standalone mode error handling' => sub {
    # Test with non-existent path
    my $out = `$TOOL /nonexistent/path/that/does/not/exist 2>&1`;
    my $exit = $? >> 8;
    
    isnt( $exit, 0, 'Exit code is non-zero for invalid path' );
    like( $out, qr/Error/i, 'Output contains error message' );
};

subtest 'MCP mode still works (backward compatibility)' => sub {
    my $dir = create_test_repo();
    
    # Test JSON input via stdin
    my $out = `echo '{"path": "$dir", "compress": true}' | $TOOL 2>&1`;
    my $exit = $? >> 8;
    
    is( $exit, 0, 'Exit code is 0' );
    like( $out, qr/"success"\s*:\s*(true|1)/i, 'JSON output has success field' );
    like( $out, qr/"metadata"/i, 'JSON output has metadata' );
    like( $out, qr/"content"/i, 'JSON output has content' );
    unlike( $out, qr/^#/m, 'No markdown headers in JSON mode' );
};

subtest 'MCP mode via --input flag' => sub {
    my $dir = create_test_repo();
    
    my $out = `$TOOL --input '{"path": "$dir"}' 2>&1`;
    my $exit = $? >> 8;
    
    is( $exit, 0, 'Exit code is 0' );
    like( $out, qr/"success"\s*:\s*(true|1)/i, 'JSON output has success' );
    like( $out, qr/"content"/i, 'JSON output has content' );
};

subtest 'Schema output (MCP mode)' => sub {
    my $out = `$TOOL --schema 2>&1`;
    my $exit = $? >> 8;
    
    is( $exit, 0, 'Exit code is 0' );
    like( $out, qr/"name"\s*:\s*"dump_repo_context"/i, 'Schema has correct name' );
    like( $out, qr/"input_schema"/i, 'Schema has input_schema' );
    like( $out, qr/"properties"/i, 'Schema has properties' );
};

subtest 'Standalone mode output to stdout, status to stderr' => sub {
    my $dir = create_test_repo();
    
    # Capture stdout and stderr separately
    my $stdout = `$TOOL $dir 2>/dev/null`;
    my $stderr = `$TOOL $dir 2>&1 >/dev/null`;
    
    # stdout should have markdown content
    like( $stdout, qr/# Repository Context Dump/i, 'Stdout has markdown content' );
    like( $stdout, qr/FILE CONTENTS/i, 'Stdout has file contents' );
    unlike( $stdout, qr/Analyzing/i, 'Stdout does not have status messages' );
    
    # stderr should have status messages
    like( $stderr, qr/Analyzing/i, 'Stderr has analyzing message' );
    like( $stderr, qr/Analysis complete/i, 'Stderr has completion message' );
    unlike( $stderr, qr/FILE CONTENTS/i, 'Stderr does not have content' );
};

subtest 'Standalone mode with current directory dot notation' => sub {
    my $dir = create_test_repo();
    my $cwd = getcwd();
    chdir($dir);
    
    my $out = `$TOOL . 2>&1`;
    my $exit = $? >> 8;
    
    chdir($cwd);
    
    is( $exit, 0, 'Exit code is 0' );
    like( $out, qr/REPO OVERVIEW/i, 'Output contains overview' );
    like( $out, qr/README\.md/i, 'Output includes files' );
};

done_testing();
