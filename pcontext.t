#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path remove_tree);
use Cwd qw(abs_path getcwd);

# Test that the script exists and is executable
my $script_path = './pcontext.pl';
ok( -f $script_path, 'pcontext.pl exists' );
ok( -x $script_path, 'pcontext.pl is executable' );

# Test that the script compiles
my $compile_result = `perl -c $script_path 2>&1`;
like( $compile_result, qr/syntax OK/, 'pcontext.pl compiles without errors' );

# Test: Basic script functionality - help option
{
    my $output = `./pcontext.pl --help 2>&1`;
    like( $output, qr/Usage:/, 'Help message contains Usage section' );
    like( $output, qr/Examples:/, 'Help message contains Examples section' );
    like( $output, qr/--git_url/, 'Help message mentions --git_url option' );
}

# Test: Script with non-existent path
{
    my $output = `./pcontext.pl /nonexistent/path 2>&1`;
    like( $output, qr/not found|not a directory/i,
        'Script reports error for non-existent path' );
    my $exit_code = $? >> 8;
    isnt( $exit_code, 0, 'Script exits with non-zero for invalid path' );
}

# Test: Integration test - script execution on test directory
{
    my $test_dir = tempdir( CLEANUP => 1 );
    make_path("$test_dir/src");
    make_path("$test_dir/test");

    # Create test files
    open my $fh, '>', "$test_dir/README.md"    or die "Cannot create file: $!";
    print $fh "# Test Project\n";
    close $fh;

    open $fh, '>', "$test_dir/src/main.py" or die "Cannot create file: $!";
    print $fh "def main():\n    print('Hello')\n";
    close $fh;

    open $fh, '>', "$test_dir/test/test_main.py"
      or die "Cannot create file: $!";
    print $fh "def test_main():\n    assert True\n";
    close $fh;

    my $output = `./pcontext.pl $test_dir 2>&1`;
    like( $output, qr/REPO OVERVIEW/,      'Script output contains REPO OVERVIEW' );
    like( $output, qr/LANGUAGE OVERVIEW/,  'Script output contains LANGUAGE OVERVIEW' );
    like( $output, qr/REPO TREE/,          'Script output contains REPO TREE' );
    like( $output, qr/FILE CONTENTS/,      'Script output contains FILE CONTENTS' );
    like( $output, qr/README\.md/,         'Script output includes README.md' );
    like( $output, qr/main\.py/,           'Script output includes main.py' );
    like( $output, qr/test_main\.py/,      'Script output includes test_main.py' );
}

# Test: Environment variable configuration
{
    my $test_dir = tempdir( CLEANUP => 1 );
    
    # Create a Python file
    open my $fh, '>', "$test_dir/example.py" or die "Cannot create file: $!";
    print $fh "print('test')\n";
    close $fh;
    
    # Create a JavaScript file
    open $fh, '>', "$test_dir/example.js" or die "Cannot create file: $!";
    print $fh "console.log('test');\n";
    close $fh;
    
    # Test REPO_DUMP_ONLY_EXT filtering
    local $ENV{REPO_DUMP_ONLY_EXT} = 'py';
    my $output = `./pcontext.pl $test_dir 2>&1`;
    like( $output, qr/example\.py/, 'REPO_DUMP_ONLY_EXT includes .py files' );
    like( $output, qr/```python:example\.py/, 'REPO_DUMP_ONLY_EXT shows .py file content' );
    unlike( $output, qr/```javascript:example\.js/, 'REPO_DUMP_ONLY_EXT excludes .js file content' );
}

# Test: .gitignore functionality
{
    my $test_dir = tempdir( CLEANUP => 1 );
    
    # Create .gitignore
    open my $fh, '>', "$test_dir/.gitignore" or die "Cannot create file: $!";
    print $fh "*.log\n";
    print $fh "ignored_dir/\n";
    close $fh;
    
    # Create files
    open $fh, '>', "$test_dir/included.txt" or die "Cannot create file: $!";
    print $fh "This should be included\n";
    close $fh;
    
    open $fh, '>', "$test_dir/test.log" or die "Cannot create file: $!";
    print $fh "This should be ignored\n";
    close $fh;
    
    make_path("$test_dir/ignored_dir");
    open $fh, '>', "$test_dir/ignored_dir/file.txt" or die "Cannot create file: $!";
    print $fh "This should also be ignored\n";
    close $fh;
    
    my $output = `./pcontext.pl $test_dir 2>&1`;
    like( $output, qr/included\.txt/, '.gitignore allows included.txt' );
    unlike( $output, qr/test\.log/, '.gitignore excludes .log files' );
    unlike( $output, qr/FILE START: ignored_dir\/file\.txt/, '.gitignore excludes files in ignored_dir' );
}

# Test: Language detection for various file types
{
    my $test_dir = tempdir( CLEANUP => 1 );
    
    # Create files for various languages
    my %files = (
        'test.py'   => 'Python',
        'test.js'   => 'JavaScript',
        'test.rb'   => 'Ruby',
        'test.go'   => 'Go',
        'test.rs'   => 'Rust',
        'test.java' => 'Java',
        'test.c'    => 'C',
        'test.cpp'  => 'C\+\+',
    );
    
    for my $file ( keys %files ) {
        open my $fh, '>', "$test_dir/$file" or die "Cannot create file: $!";
        print $fh "// test code\n";
        close $fh;
    }
    
    my $output = `./pcontext.pl $test_dir 2>&1`;
    
    for my $file ( keys %files ) {
        my $lang = $files{$file};
        like( $output, qr/$file/, "Output includes $file" );
        like( $output, qr/$lang/, "Output detects $lang for $file" );
    }
}

# Test: File role classification
{
    my $test_dir = tempdir( CLEANUP => 1 );
    make_path("$test_dir/test");
    
    # Create files with different roles
    open my $fh, '>', "$test_dir/README.md" or die "Cannot create file: $!";
    print $fh "# Documentation\n";
    close $fh;
    
    open $fh, '>', "$test_dir/package.json" or die "Cannot create file: $!";
    print $fh "{\"name\": \"test\"}\n";
    close $fh;
    
    open $fh, '>', "$test_dir/app.py" or die "Cannot create file: $!";
    print $fh "def main(): pass\n";
    close $fh;
    
    open $fh, '>', "$test_dir/test/test_app.py" or die "Cannot create file: $!";
    print $fh "def test_main(): pass\n";
    close $fh;
    
    my $output = `./pcontext.pl $test_dir 2>&1`;
    like( $output, qr/docs|Documentation/i, 'README.md classified as documentation' );
    like( $output, qr/config|manifest/i, 'package.json classified as config/manifest' );
    like( $output, qr/entrypoint|entry/i, 'app.py classified as entrypoint' );
    like( $output, qr/test/i, 'test_app.py classified as test' );
}

# Test: Line number feature
{
    my $test_dir = tempdir( CLEANUP => 1 );
    
    open my $fh, '>', "$test_dir/code.txt" or die "Cannot create file: $!";
    print $fh "line 1\n";
    print $fh "line 2\n";
    print $fh "line 3\n";
    close $fh;
    
    # Test with line numbers enabled
    local $ENV{REPO_DUMP_LINE_NUMBERS} = 1;
    my $output = `./pcontext.pl $test_dir 2>&1`;
    like( $output, qr/1\|.*line 1/, 'Line numbers enabled: shows line 1' );
    like( $output, qr/2\|.*line 2/, 'Line numbers enabled: shows line 2' );
    
    # Test without line numbers
    delete $ENV{REPO_DUMP_LINE_NUMBERS};
    $output = `./pcontext.pl $test_dir 2>&1`;
    like( $output, qr/line 1/, 'Line numbers disabled: content is present' );
    unlike( $output, qr/1\|/, 'Line numbers disabled: no line number prefix' );
}

# Test: Max file size filtering
{
    my $test_dir = tempdir( CLEANUP => 1 );
    
    # Create a small file
    open my $fh, '>', "$test_dir/small.txt" or die "Cannot create file: $!";
    print $fh "small content\n";
    close $fh;
    
    # Create a large file
    open $fh, '>', "$test_dir/large.txt" or die "Cannot create file: $!";
    print $fh "x" x 10000;  # 10KB
    close $fh;
    
    # Set max bytes to 5KB
    local $ENV{REPO_DUMP_MAX_BYTES} = 5000;
    my $output = `./pcontext.pl $test_dir 2>&1`;
    
    like( $output, qr/small\.txt/, 'Small file is included' );
    like( $output, qr/small content/, 'Small file content is shown' );
    like( $output, qr/large\.txt/, 'Large file is listed' );
    like( $output, qr/FILE TOO LARGE|CONTENT OMITTED/i, 'Large file content is omitted' );
}

# Test: Exclude pattern functionality
{
    my $test_dir = tempdir( CLEANUP => 1 );
    
    open my $fh, '>', "$test_dir/keep.txt" or die "Cannot create file: $!";
    print $fh "keep\n";
    close $fh;
    
    open $fh, '>', "$test_dir/exclude.tmp" or die "Cannot create file: $!";
    print $fh "exclude\n";
    close $fh;
    
    local $ENV{REPO_DUMP_EXCLUDE} = '*.tmp';
    my $output = `./pcontext.pl $test_dir 2>&1`;
    
    like( $output, qr/keep\.txt/, 'REPO_DUMP_EXCLUDE keeps non-matching files' );
    unlike( $output, qr/exclude\.tmp/, 'REPO_DUMP_EXCLUDE filters matching files' );
}

# Test: Current directory execution
{
    my $cwd = getcwd();
    my $output = `./pcontext.pl . 2>&1`;
    like( $output, qr/REPO OVERVIEW/, 'Script works with current directory (.)' );
    like( $output, qr/pcontext\.pl/, 'Script includes itself when run on current directory' );
}

done_testing();
