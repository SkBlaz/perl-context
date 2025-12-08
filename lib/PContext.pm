package PContext;

use strict;
use warnings;
use utf8;
use File::Find;
use File::Spec;
use File::Path 'remove_tree';
use File::Temp 'tempdir';
use Cwd 'abs_path';
use Exporter 'import';

our @EXPORT_OK = qw(
    analyze_repository
    clone_git_repo
    get_default_config
    lang_display_name
);

our $VERSION = '1.0.0';

# Global for cleanup
our $tmp_root;

# Register cleanup for the temp directory
END {
    if ( defined $tmp_root && -d $tmp_root ) {
        remove_tree( $tmp_root, { error => \my $err } );
    }
}

# ------------------------------------------------------------
# Language mapping
# ------------------------------------------------------------

my %ext_to_lang = (
    pl       => 'perl',
    pm       => 'perl',
    t        => 'perl',
    py       => 'python',
    pyw      => 'python',
    pyi      => 'python',
    rb       => 'ruby',
    erb      => 'ruby',
    rake     => 'ruby',
    js       => 'javascript',
    mjs      => 'javascript',
    cjs      => 'javascript',
    ts       => 'typescript',
    tsx      => 'tsx',
    jsx      => 'jsx',
    java     => 'java',
    c        => 'c',
    h        => 'c',
    cpp      => 'cpp',
    cc       => 'cpp',
    cxx      => 'cpp',
    hh       => 'cpp',
    hpp      => 'cpp',
    hxx      => 'cpp',
    go       => 'go',
    rs       => 'rust',
    php      => 'php',
    cs       => 'csharp',
    fs       => 'fsharp',
    sh       => 'bash',
    bash     => 'bash',
    zsh      => 'zsh',
    fish     => 'fish',
    ps1      => 'powershell',
    psm1     => 'powershell',
    md       => 'markdown',
    markdown => 'markdown',
    rst      => 'rst',
    json     => 'json',
    jsonc    => 'json',
    yml      => 'yaml',
    yaml     => 'yaml',
    html     => 'html',
    htm      => 'html',
    xhtml    => 'html',
    css      => 'css',
    scss     => 'scss',
    sass     => 'sass',
    less     => 'less',
    sql      => 'sql',
    kt       => 'kotlin',
    kts      => 'kotlin',
    swift    => 'swift',
    r        => 'r',
    R        => 'r',
    hs       => 'haskell',
    lhs      => 'haskell',
    toml     => 'toml',
    ini      => 'ini',
    cfg      => 'ini',
    xml      => 'xml',
    xsl      => 'xml',
    vue      => 'vue',
    svelte   => 'svelte',
    lua      => 'lua',
    ex       => 'elixir',
    exs      => 'elixir',
    erl      => 'erlang',
    hrl      => 'erlang',
    clj      => 'clojure',
    cljs     => 'clojure',
    scala    => 'scala',
    sc       => 'scala',
    dart     => 'dart',
    zig      => 'zig',
    nim      => 'nim',
    v        => 'v',
    proto    => 'protobuf',
    graphql  => 'graphql',
    gql      => 'graphql',
    tf       => 'terraform',
    tfvars   => 'terraform',
    dockerfile => 'dockerfile',
    makefile   => 'makefile',
);

my %lang_name = (
    perl       => 'Perl',
    python     => 'Python',
    ruby       => 'Ruby',
    javascript => 'JavaScript',
    typescript => 'TypeScript',
    tsx        => 'TypeScript (TSX)',
    jsx        => 'JavaScript (JSX)',
    java       => 'Java',
    c          => 'C',
    cpp        => 'C++',
    go         => 'Go',
    rust       => 'Rust',
    php        => 'PHP',
    csharp     => 'C#',
    fsharp     => 'F#',
    bash       => 'Shell (bash)',
    zsh        => 'Shell (zsh)',
    fish       => 'Fish',
    powershell => 'PowerShell',
    markdown   => 'Markdown',
    rst        => 'reStructuredText',
    json       => 'JSON',
    yaml       => 'YAML',
    html       => 'HTML',
    css        => 'CSS',
    scss       => 'SCSS',
    sass       => 'Sass',
    less       => 'Less',
    sql        => 'SQL',
    kotlin     => 'Kotlin',
    swift      => 'Swift',
    r          => 'R',
    haskell    => 'Haskell',
    toml       => 'TOML',
    ini        => 'INI',
    xml        => 'XML',
    vue        => 'Vue',
    svelte     => 'Svelte',
    lua        => 'Lua',
    elixir     => 'Elixir',
    erlang     => 'Erlang',
    clojure    => 'Clojure',
    scala      => 'Scala',
    dart       => 'Dart',
    zig        => 'Zig',
    nim        => 'Nim',
    v          => 'V',
    protobuf   => 'Protocol Buffers',
    graphql    => 'GraphQL',
    terraform  => 'Terraform',
    dockerfile => 'Dockerfile',
    makefile   => 'Makefile',
    cmake      => 'CMake',
    gitignore  => 'Git Ignore',
    dockerignore => 'Docker Ignore',
    editorconfig => 'EditorConfig',
    text       => 'Text / other',
);

sub lang_display_name {
    my ($k) = @_;
    $k ||= 'text';
    return $lang_name{$k} || ucfirst($k);
}

sub get_lang_key {
    my ($ext) = @_;
    return '' unless defined $ext && length $ext;
    return $ext_to_lang{ lc($ext) } || '';
}

# Shebang to language mapping
my %shebang_to_lang = (
    'perl'    => 'perl',
    'python'  => 'python',
    'python3' => 'python',
    'python2' => 'python',
    'ruby'    => 'ruby',
    'node'    => 'javascript',
    'nodejs'  => 'javascript',
    'bash'    => 'bash',
    'sh'      => 'bash',
    'zsh'     => 'zsh',
    'fish'    => 'fish',
    'php'     => 'php',
    'lua'     => 'lua',
    'ruby'    => 'ruby',
    'Rscript' => 'r',
    'pwsh'    => 'powershell',
);

sub detect_lang_from_shebang {
    my ($filepath) = @_;
    return '' unless defined $filepath && -f $filepath && -r $filepath && -T $filepath;

    open my $fh, '<', $filepath or return '';
    my $first_line = <$fh>;
    close $fh;

    return '' unless defined $first_line && $first_line =~ /^#!/;

    # Parse shebang: #!/usr/bin/env perl, #!/usr/bin/perl, etc.
    if ( $first_line =~ m{^#!\s*/usr/bin/env\s+(\S+)} ) {
        my $cmd = $1;
        return $shebang_to_lang{$cmd} || '';
    }
    elsif ( $first_line =~ m{^#!\s*\S+/(\w+)} ) {
        my $cmd = $1;
        return $shebang_to_lang{$cmd} || '';
    }

    return '';
}

# Filename to language mapping for extensionless files
my %filename_to_lang = (
    'makefile'     => 'makefile',
    'gnumakefile'  => 'makefile',
    'dockerfile'   => 'dockerfile',
    'vagrantfile'  => 'ruby',
    'gemfile'      => 'ruby',
    'rakefile'     => 'ruby',
    'procfile'     => 'yaml',
    'brewfile'     => 'ruby',
    'justfile'     => 'makefile',
    'cmakelists.txt' => 'cmake',
);

sub detect_lang_from_filename {
    my ($rel) = @_;
    return '' unless defined $rel;

    my ($filename) = $rel =~ m{([^/]+)$};
    return '' unless $filename;

    return $filename_to_lang{ lc($filename) } || '';
}

# ------------------------------------------------------------
# Git operations
# ------------------------------------------------------------

sub clone_git_repo {
    my ($git_url) = @_;

    return { error => 'git_url is required' } unless $git_url;

    $tmp_root = tempdir( "pcontext-XXXXXX", CLEANUP => 0, TMPDIR => 1 );
    my $target = "$tmp_root/repo";

    my @cmd = ( 'git', 'clone', '--depth', '1', '--quiet', $git_url, $target );
    my $rc = system(@cmd);

    if ( $rc != 0 ) {
        my $exit_code = $rc >> 8;
        return {
            error => "git clone failed",
            code => "GIT_CLONE_FAILED",
            details => "Exit code: $exit_code"
        };
    }

    return { path => abs_path($target) };
}

# ------------------------------------------------------------
# .gitignore + extra excludes
# ------------------------------------------------------------

sub glob_to_regex {
    my ($pat) = @_;
    $pat =~ s/^\s+|\s+$//g;
    return if not $pat or $pat =~ /^#/;
    return if $pat =~ s/^!//;    # ignore negated

    my $re = quotemeta($pat);
    $re =~ s{/\\*\\*$}{/.*}g;    # /** at end
    $re =~ s{\\\*\\\*}{.*}g;     # **
    $re =~ s{\\\*}{[^/]*}g;      # *
    $re =~ s{\\\?}{[^/]}g;       # ?

    if ( substr( $pat, 0, 1 ) eq '/' ) {
        return qr{^$re};
    }
    else {
        return qr{(?:^|/)$re};
    }
}

sub build_ignore_list {
    my ( $root, $exclude_patterns ) = @_;
    my @ignore_re;
    my $gitignore = "$root/.gitignore";

    if ( -f $gitignore && open my $gi, '<', $gitignore ) {
        while ( my $pat = <$gi> ) {
            chomp $pat;
            my $re = glob_to_regex($pat);
            push @ignore_re, $re if $re;
        }
        close $gi;
    }

    if ( ref $exclude_patterns eq 'ARRAY' ) {
        for my $pat (@$exclude_patterns) {
            my $re = glob_to_regex($pat);
            push @ignore_re, $re if $re;
        }
    }
    elsif ( defined $exclude_patterns && length $exclude_patterns ) {
        for my $pat ( split /\s*,\s*/, $exclude_patterns ) {
            my $re = glob_to_regex($pat);
            push @ignore_re, $re if $re;
        }
    }

    return \@ignore_re;
}

sub is_ignored {
    my ( $rel, $ignore_re ) = @_;
    for my $re (@$ignore_re) {
        return 1 if $rel =~ $re;
    }
    return 0;
}

# ------------------------------------------------------------
# Role & hint classification
# ------------------------------------------------------------

sub classify_file {
    my ( $rel, $ext, $lang_key ) = @_;
    my $lc = lc $rel;
    my $category;
    my $is_config = 0;
    my $is_entry  = 0;

    # Entrypoints by language
    if ( $lang_key && $lang_key eq 'python' ) {
        $is_entry = 1 if $lc =~ m{(^|/)(main|app|wsgi|asgi|manage|cli|__main__)\.py$};
    }
    elsif ( $lang_key && $lang_key =~ /^(javascript|typescript|tsx|jsx)$/ ) {
        $is_entry = 1
          if $lc =~ m{(^|/)(src/)?(index|main|app|server|cli)\.(js|jsx|ts|tsx)$};
    }
    elsif ( $lang_key && $lang_key eq 'go' ) {
        $is_entry = 1
          if $lc =~ m{(^|/)cmd/[^/]+/main\.go$} || $lc =~ m{(^|/)main\.go$};
    }
    elsif ( $lang_key && $lang_key eq 'rust' ) {
        $is_entry = 1
          if $lc =~ m{(^|/)src/main\.rs$} || $lc =~ m{(^|/)src/bin/[^/]+\.rs$};
    }
    elsif ( $lang_key && $lang_key eq 'java' ) {
        $is_entry = 1
          if $lc =~ m{(^|/)src/main/java/.+/(Main|Application)\.java$};
    }
    elsif ( $lang_key && $lang_key eq 'perl' ) {
        $is_entry = 1 if $lc =~ m{(^|/)(script|bin)/[^/]+\.pl$} || $lc =~ m{^[^/]+\.pl$};
    }

    # Tests
    if (   $lc =~ m{(^|/)(test|tests|spec|specs|__tests__|t)/}
        || $lc =~ m{(^|/)test_}
        || $lc =~ m{_test\.[a-z0-9_]+$}
        || $lc =~ m{\.spec\.[a-z0-9_]+$}
        || $lc =~ m{\.test\.[a-z0-9_]+$}
        || $lc =~ m{\.t$} )
    {
        $category = 'test';
    }

    # Config / manifest
    my @config_names = qw(
      package.json package-lock.json yarn.lock pnpm-lock.yaml
      tsconfig.json jsconfig.json
      webpack.config.js webpack.config.ts
      vite.config.js vite.config.ts vite.config.mjs
      rollup.config.js rollup.config.ts rollup.config.mjs
      babel.config.js babel.config.cjs babel.config.mjs babel.config.json
      jest.config.js jest.config.ts jest.config.mjs jest.config.json
      vitest.config.js vitest.config.ts vitest.config.mjs
      eslint.config.js eslint.config.mjs .eslintrc .eslintrc.js .eslintrc.json
      prettier.config.js .prettierrc .prettierrc.js .prettierrc.json
      pyproject.toml setup.py setup.cfg requirements.txt
      Pipfile Pipfile.lock poetry.lock
      tox.ini pytest.ini
      Cargo.toml Cargo.lock
      go.mod go.sum
      Makefile GNUmakefile makefile CMakeLists.txt
      pom.xml build.gradle build.gradle.kts settings.gradle settings.gradle.kts
      composer.json composer.lock
      Gemfile Gemfile.lock Rakefile
      .github/workflows
      Dockerfile docker-compose.yml docker-compose.yaml
      .env.example .env.sample
      renovate.json .renovaterc
      .gitlab-ci.yml .travis.yml azure-pipelines.yml
    );

    for my $cfg (@config_names) {
        my $pat = lc $cfg;
        if ( index( $lc, "/$pat" ) >= 0 || substr( $lc, -length($pat) ) eq $pat ) {
            $category  = 'config' unless defined $category;
            $is_config = 1;
            last;
        }
    }

    # CI/CD
    if ( !defined $category && $lc =~ m{\.github/workflows/} ) {
        $category  = 'config';
        $is_config = 1;
    }

    # Docs
    if (   !defined $category
        && $lc  =~ m{(^|/)(docs?|documentation)/}
        && $ext =~ /^(md|rst|txt|adoc|html)$/i )
    {
        $category = 'docs';
    }
    if ( !defined $category
        && $lc =~ m{(^|/)(readme|changelog|changes|history|license|copying|contributing|authors|code_of_conduct)(\.|$)}i )
    {
        $category = 'docs';
    }

    # Fallback
    if ( !defined $category ) {
        if ( defined $lang_key && $lang_key ne '' && $ext !~ /^(md|txt|rst)$/i ) {
            $category = 'source';
        }
        else {
            $category = 'other';
        }
    }

    return {
        category  => $category,
        is_config => $is_config,
        is_entry  => $is_entry,
    };
}

sub get_role_hint {
    my ($file_info) = @_;
    my @bits;

    push @bits, 'probable application entrypoint' if $file_info->{is_entry};

    my $category = $file_info->{category};
    my $lang_key = $file_info->{lang_key};
    my $rel      = $file_info->{rel};

    if ( $category eq 'test' ) {
        if ( $lang_key && $lang_key eq 'python' ) {
            push @bits, 'Python tests (pytest/unittest style)';
        }
        elsif ( $lang_key && $lang_key =~ /^(javascript|typescript|tsx|jsx)$/ ) {
            push @bits, 'JS/TS tests (Jest/Vitest/Mocha style)';
        }
        elsif ( $lang_key && $lang_key eq 'go' ) {
            push @bits, 'Go tests (*_test.go)';
        }
        elsif ( $lang_key && $lang_key eq 'rust' ) {
            push @bits, 'Rust tests';
        }
        elsif ( $lang_key && $lang_key eq 'perl' ) {
            push @bits, 'Perl tests (Test::More style)';
        }
        else {
            push @bits, 'Test code';
        }
    }

    push @bits, 'Documentation / README-style content' if $category eq 'docs';

    if ( $category eq 'config' && $file_info->{is_config} ) {
        my $lc = lc $rel;
        if    ( $lc =~ /package\.json$/i )      { push @bits, 'Node.js package manifest'; }
        elsif ( $lc =~ /pyproject\.toml$/i )    { push @bits, 'Python project configuration (PEP 621)'; }
        elsif ( $lc =~ /requirements\.txt$/i )  { push @bits, 'Python dependencies list'; }
        elsif ( $lc =~ /Cargo\.toml$/i )        { push @bits, 'Rust crate manifest'; }
        elsif ( $lc =~ /go\.mod$/i )            { push @bits, 'Go module definition'; }
        elsif ( $lc =~ /pom\.xml$/i )           { push @bits, 'Maven build configuration'; }
        elsif ( $lc =~ /docker-compose/i )      { push @bits, 'Docker Compose configuration'; }
        elsif ( $lc =~ /dockerfile/i )          { push @bits, 'Docker container definition'; }
        elsif ( $lc =~ /\.github\/workflows/i ) { push @bits, 'GitHub Actions workflow'; }
    }

    return join( ', ', @bits );
}

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

sub get_default_config {
    return {
        max_bytes      => 300_000,
        max_lines      => 1200,
        line_nums      => 0,
        only_ext       => {},
        exclude_pat    => [],
        compress       => 0,
        output_format  => 'markdown',
        max_output     => 0,
    };
}

sub build_config {
    my ($params) = @_;
    my $config = get_default_config();

    $config->{max_bytes} = $params->{max_file_size} if defined $params->{max_file_size};
    $config->{max_lines} = $params->{max_lines_per_chunk} if defined $params->{max_lines_per_chunk};
    $config->{line_nums} = $params->{include_line_numbers} ? 1 : 0;
    $config->{compress}  = $params->{compress} ? 1 : 0;
    $config->{output_format} = $params->{output_format} || 'markdown';
    $config->{max_output} = $params->{max_total_output_bytes} || 0;

    if ( ref $params->{include_extensions} eq 'ARRAY' && @{ $params->{include_extensions} } ) {
        $config->{only_ext} = { map { lc($_) => 1 } @{ $params->{include_extensions} } };
    }

    if ( ref $params->{exclude_patterns} eq 'ARRAY' ) {
        $config->{exclude_pat} = $params->{exclude_patterns};
    }

    return $config;
}

# ------------------------------------------------------------
# Repository walking
# ------------------------------------------------------------

sub walk_repo {
    my ( $root, $config, $ignore_re ) = @_;

    my @paths;
    my @files;
    my %is_dir;

    find(
        {
            no_chdir => 1,
            wanted   => sub {
                my $path = $File::Find::name;
                return if $path eq $root;

                # Check if directory and should be pruned
                # Note: Use -d $path, not -d _ (stat cache unreliable with no_chdir)
                if ( -d $path ) {
                    my ($name) = $path =~ m{([^/]+)$};
                    if (   $name =~ /^\.(git|svn|hg|bzr)$/
                        || $name =~ /^(node_modules|dist|build|target|venv|\.venv|__pycache__|\.cache|\.next|\.nuxt|coverage|\.pytest_cache|\.mypy_cache)$/ )
                    {
                        $File::Find::prune = 1;
                        return;
                    }
                }

                my $rel = File::Spec->abs2rel( $path, $root );
                return if is_ignored( $rel, $ignore_re );

                push @paths, $rel;
                if ( -d $path ) {
                    $is_dir{$rel} = 1;
                }
                elsif ( -f $path ) {
                    if ( %{ $config->{only_ext} } ) {
                        my ($ext) = $rel =~ /\.([A-Za-z0-9_]+)$/;
                        my $lang_ext = lc( $ext // '' );
                        return if !$lang_ext || !$config->{only_ext}{$lang_ext};
                    }
                    push @files, $rel;
                }
            },
        },
        $root
    );

    @paths = sort @paths;
    @files = sort @files;

    return {
        paths  => \@paths,
        files  => \@files,
        is_dir => \%is_dir,
    };
}

# ------------------------------------------------------------
# Statistics and metadata collection
# ------------------------------------------------------------

sub collect_file_info {
    my ( $walk_result, $root ) = @_;

    my %file_info;
    my %lang_stats;
    my %ext_count;
    my $total_bytes = 0;
    my $dir_count   = 0;

    for my $p ( @{ $walk_result->{paths} } ) {
        $dir_count++ if $walk_result->{is_dir}{$p};
    }

    for my $rel ( @{ $walk_result->{files} } ) {
        my $full    = "$root/$rel";
        my $size    = -s $full // 0;
        my $is_text = -T $full;

        $total_bytes += $size;

        my ($ext) = $rel =~ /\.([A-Za-z0-9_]+)$/;
        my $lang_ext = lc( $ext // '' );
        $ext_count{$lang_ext}++ if $lang_ext;

        # Try extension, then filename, then shebang detection
        my $lang_key = get_lang_key($lang_ext);
        if ( !$lang_key ) {
            $lang_key = detect_lang_from_filename($rel);
        }
        if ( !$lang_key && $is_text ) {
            $lang_key = detect_lang_from_shebang($full);
        }
        my $lang_id   = $lang_key || $lang_ext || 'text';
        my $lang_name = lang_display_name($lang_id);

        my $classification = classify_file( $rel, $lang_ext, $lang_key );

        $file_info{$rel} = {
            rel       => $rel,
            full      => $full,
            size      => $size,
            is_text   => $is_text,
            ext       => $lang_ext,
            lang_key  => $lang_key,
            lang_id   => $lang_id,
            lang_name => $lang_name,
            category  => $classification->{category},
            is_config => $classification->{is_config},
            is_entry  => $classification->{is_entry},
        };

        my $stats = $lang_stats{$lang_id} ||= {
            name    => $lang_name,
            count   => 0,
            bytes   => 0,
            by_role => {},
            entries => [],
            configs => [],
        };

        $stats->{count}++;
        $stats->{bytes} += $size;
        $stats->{by_role}{ $classification->{category} }++;
        push @{ $stats->{entries} }, $rel if $classification->{is_entry};
        push @{ $stats->{configs} }, $rel if $classification->{is_config};
    }

    return {
        file_info   => \%file_info,
        lang_stats  => \%lang_stats,
        ext_count   => \%ext_count,
        total_bytes => $total_bytes,
        dir_count   => $dir_count,
        file_count  => scalar @{ $walk_result->{files} },
    };
}

sub select_key_files {
    my ( $files, $file_info ) = @_;
    my @key_files;

    for my $rel (@$files) {
        my $info = $file_info->{$rel} or next;
        if ( $info->{category} eq 'docs' || $info->{is_entry} || $info->{is_config} ) {
            push @key_files, $rel;
        }
    }

    return \@key_files;
}

# ------------------------------------------------------------
# Output generation - Markdown
# ------------------------------------------------------------

sub generate_markdown_overview {
    my ($data) = @_;
    my $out = '';

    my $approx_tokens = int( ( $data->{total_bytes} || 0 ) / 4 );

    $out .= "### REPO OVERVIEW\n\n";
    $out .= "Root: $data->{root}\n";
    $out .= "Dirs: $data->{dir_count}\n";
    $out .= "Files (included by filters): $data->{file_count}\n";
    $out .= "Approx total bytes: $data->{total_bytes}\n";
    $out .= "Approx tokens (~4 chars/token): $approx_tokens\n\n";

    if ( @{ $data->{key_files} } ) {
        $out .= "Key docs / entrypoints / configs:\n";
        for my $kf ( sort @{ $data->{key_files} } ) {
            my $info = $data->{file_info}{$kf};
            my $tag  = $info->{category};
            $tag .= ", entrypoint" if $info->{is_entry};
            $tag .= ", config"     if $info->{is_config};
            $out .= "- $kf [$tag]\n";
        }
        $out .= "\n";
    }

    if ( %{ $data->{ext_count} } ) {
        $out .= "By extension:\n";
        for my $e ( sort { $data->{ext_count}{$b} <=> $data->{ext_count}{$a} || $a cmp $b }
                    keys %{ $data->{ext_count} } )
        {
            $out .= "- $e: $data->{ext_count}{$e}\n";
        }
        $out .= "\n";
    }

    return $out;
}

sub generate_markdown_languages {
    my ($lang_stats) = @_;
    my $out = "### LANGUAGE OVERVIEW\n\n";

    for my $lang_id (
        sort {
            ( $lang_stats->{$b}{bytes} <=> $lang_stats->{$a}{bytes} )
              || ( $lang_stats->{$b}{count} <=> $lang_stats->{$a}{count} )
              || ( $lang_stats->{$a}{name} cmp $lang_stats->{$b}{name} )
        } keys %$lang_stats )
    {
        my $stats  = $lang_stats->{$lang_id};
        my $tokens = int( ( $stats->{bytes} || 0 ) / 4 );

        $out .= "- $stats->{name} ($lang_id): $stats->{count} files, ~$tokens tokens\n";

        my @roles = qw(source test config docs other);
        my @role_lines;
        for my $r (@roles) {
            my $c = $stats->{by_role}{$r} || 0;
            push @role_lines, "$r=$c" if $c;
        }
        $out .= "  Roles: " . join( ', ', @role_lines ) . "\n" if @role_lines;

        if ( @{ $stats->{entries} || [] } ) {
            $out .= "  Entry-point files:\n";
            $out .= "    - $_\n" for @{ $stats->{entries} };
        }

        if ( @{ $stats->{configs} || [] } ) {
            $out .= "  Config files:\n";
            $out .= "    - $_\n" for @{ $stats->{configs} };
        }

        $out .= "\n";
    }

    return $out;
}

sub generate_markdown_tree {
    my ( $paths, $is_dir ) = @_;
    my $out = "### REPO TREE\n\n";

    for my $p (@$paths) {
        my @parts  = split m{/}, $p;
        my $indent = '  ' x ( @parts - 1 );
        my $name   = $parts[-1];
        my $slash  = $is_dir->{$p} ? '/' : '';
        $out .= "$indent$name$slash\n";
    }

    return $out;
}

sub generate_markdown_contents {
    my ( $files, $file_info, $config, $root ) = @_;
    my $out = '';

    if ( $config->{compress} ) {
        $out .= "\n### FILE LIST\n";
        $out .= "# Compressed mode: metadata only (no contents).\n\n";

        for my $rel (@$files) {
            my $info = $file_info->{$rel} or next;
            my $text_indicator = $info->{is_text} ? 'text' : 'binary';
            $out .= "- $rel [$info->{lang_name}, $info->{category}, $info->{size} bytes, $text_indicator]\n";
        }
        return $out;
    }

    $out .= "\n### FILE CONTENTS\n";
    $out .= "# Files wrapped in markers and code fences for LLM consumption.\n\n";

    my $use_chunks = $config->{max_lines} && $config->{max_lines} > 0;

    for my $rel (@$files) {
        my $info = $file_info->{$rel} or next;
        my $hint = get_role_hint($info);

        $out .= "\n=== FILE START: $rel ===\n";
        $out .= "Size: $info->{size} bytes | Text: " . ( $info->{is_text} ? 'yes' : 'no' ) . "\n";
        $out .= "Language: $info->{lang_name} ($info->{lang_id}) | Role: $info->{category}\n";
        $out .= "Hints: $hint\n" if $hint;
        $out .= "Chunks: " . ( $use_chunks ? "up to $config->{max_lines} lines" : 'single' ) . "\n";

        if ( !$info->{is_text} ) {
            $out .= "[[ BINARY FILE - CONTENT OMITTED ]]\n";
            $out .= "=== FILE END: $rel ===\n";
            next;
        }

        if ( $info->{size} > $config->{max_bytes} ) {
            $out .= "[[ FILE TOO LARGE (> $config->{max_bytes} bytes) - CONTENT OMITTED ]]\n";
            $out .= "=== FILE END: $rel ===\n";
            next;
        }

        my $fh;
        unless ( open $fh, '<', $info->{full} ) {
            $out .= "[[ ERROR: cannot open file ]]\n";
            $out .= "=== FILE END: $rel ===\n";
            next;
        }

        my $chunk         = 1;
        my $line_in_chunk = 0;
        my $line_in_file  = 0;

        my $fence_lang = $info->{lang_id};
        $fence_lang =~ s/\s+/_/g;
        my $fence_info = $fence_lang ? "$fence_lang:$rel" : $rel;

        $out .= "\n";
        $out .= "--- CHUNK $chunk of $rel ---\n" if $use_chunks;
        $out .= "```$fence_info\n";

        while ( my $l = <$fh> ) {
            $line_in_file++;

            if ($use_chunks) {
                $line_in_chunk++;
                if ( $line_in_chunk > $config->{max_lines} ) {
                    $out .= "```\n\n";
                    $chunk++;
                    $line_in_chunk = 1;
                    $out .= "--- CHUNK $chunk of $rel ---\n";
                    $out .= "```$fence_info\n";
                }
            }

            if ( $config->{line_nums} ) {
                $out .= sprintf "%5d| %s", $line_in_file, $l;
            }
            else {
                $out .= $l;
            }
        }

        close $fh;
        $out .= "```\n";
        $out .= "=== FILE END: $rel ===\n";
    }

    return $out;
}

# ------------------------------------------------------------
# Main analysis function
# ------------------------------------------------------------

sub analyze_repository {
    my ($params) = @_;
    $params ||= {};

    # Determine root path
    my $root;
    my $cloned = 0;

    if ( $params->{git_url} ) {
        my $result = clone_git_repo( $params->{git_url} );
        if ( $result->{error} ) {
            return {
                success => 0,
                error   => {
                    code    => $result->{code} || 'GIT_ERROR',
                    message => $result->{error},
                    details => $result->{details},
                },
            };
        }
        $root   = $result->{path};
        $cloned = 1;
    }
    else {
        $root = $params->{path} || '.';
        $root = abs_path($root) if -e $root;
    }

    unless ( defined $root && -d $root ) {
        return {
            success => 0,
            error   => {
                code    => 'INVALID_PATH',
                message => "Path '$root' not found or is not a directory",
            },
        };
    }

    # Build configuration
    my $config    = build_config($params);
    my $ignore_re = build_ignore_list( $root, $config->{exclude_pat} );

    # Walk repository
    my $walk_result = walk_repo( $root, $config, $ignore_re );

    if ( !@{ $walk_result->{files} } ) {
        return {
            success => 1,
            metadata => {
                root_path    => $root,
                total_files  => 0,
                total_dirs   => 0,
                total_bytes  => 0,
                approx_tokens => 0,
                languages    => {},
                key_files    => [],
            },
            content   => "# No files found matching criteria.\n",
            truncated => 0,
        };
    }

    # Collect statistics
    my $stats     = collect_file_info( $walk_result, $root );
    my $key_files = select_key_files( $walk_result->{files}, $stats->{file_info} );

    # Prepare data for output
    my $data = {
        root        => $root,
        dir_count   => $stats->{dir_count},
        file_count  => $stats->{file_count},
        total_bytes => $stats->{total_bytes},
        file_info   => $stats->{file_info},
        lang_stats  => $stats->{lang_stats},
        ext_count   => $stats->{ext_count},
        key_files   => $key_files,
        paths       => $walk_result->{paths},
        is_dir      => $walk_result->{is_dir},
        files       => $walk_result->{files},
    };

    # Generate output
    my $content;
    my $truncated = 0;

    if ( $config->{output_format} eq 'json' ) {
        # JSON output - structured data
        my $json_data = {
            root        => $root,
            statistics  => {
                total_files   => $stats->{file_count},
                total_dirs    => $stats->{dir_count},
                total_bytes   => $stats->{total_bytes},
                approx_tokens => int( $stats->{total_bytes} / 4 ),
            },
            languages   => {},
            key_files   => $key_files,
            tree        => $walk_result->{paths},
            files       => [],
        };

        # Format language stats
        for my $lang_id ( keys %{ $stats->{lang_stats} } ) {
            my $ls = $stats->{lang_stats}{$lang_id};
            $json_data->{languages}{$lang_id} = {
                name       => $ls->{name},
                file_count => $ls->{count},
                bytes      => $ls->{bytes},
                roles      => $ls->{by_role},
                entries    => $ls->{entries},
                configs    => $ls->{configs},
            };
        }

        # Format file info
        for my $rel ( @{ $walk_result->{files} } ) {
            my $info = $stats->{file_info}{$rel};
            my $file_data = {
                path      => $rel,
                size      => $info->{size},
                is_text   => $info->{is_text} ? \1 : \0,
                language  => $info->{lang_name},
                lang_id   => $info->{lang_id},
                role      => $info->{category},
                is_config => $info->{is_config} ? \1 : \0,
                is_entry  => $info->{is_entry} ? \1 : \0,
            };

            unless ( $config->{compress} ) {
                if ( $info->{is_text} && $info->{size} <= $config->{max_bytes} ) {
                    if ( open my $fh, '<', $info->{full} ) {
                        local $/;
                        $file_data->{content} = <$fh>;
                        close $fh;
                    }
                }
            }

            push @{ $json_data->{files} }, $file_data;
        }

        # Use JSON encoder if available, otherwise simple serialization
        eval { require JSON::PP };
        if ($@) {
            # Fallback: basic JSON output
            $content = _simple_json_encode($json_data);
        }
        else {
            my $json = JSON::PP->new->utf8->pretty->canonical;
            $content = $json->encode($json_data);
        }
    }
    else {
        # Markdown output
        $content = "# Repository Context Dump\n\n";
        $content .= generate_markdown_overview($data);
        $content .= generate_markdown_languages( $stats->{lang_stats} );
        $content .= generate_markdown_tree( $walk_result->{paths}, $walk_result->{is_dir} );
        $content .= generate_markdown_contents( $walk_result->{files}, $stats->{file_info}, $config, $root );
    }

    # Apply output size limit
    if ( $config->{max_output} > 0 && length($content) > $config->{max_output} ) {
        $content   = substr( $content, 0, $config->{max_output} );
        $content   .= "\n\n[[ OUTPUT TRUNCATED - exceeded $config->{max_output} bytes ]]\n";
        $truncated = 1;
    }

    # Build metadata for response
    my %lang_meta;
    for my $lang_id ( keys %{ $stats->{lang_stats} } ) {
        my $ls = $stats->{lang_stats}{$lang_id};
        $lang_meta{$lang_id} = {
            file_count => $ls->{count},
            bytes      => $ls->{bytes},
            roles      => $ls->{by_role},
        };
    }

    return {
        success  => 1,
        metadata => {
            root_path     => $root,
            total_files   => $stats->{file_count},
            total_dirs    => $stats->{dir_count},
            total_bytes   => $stats->{total_bytes},
            approx_tokens => int( $stats->{total_bytes} / 4 ),
            languages     => \%lang_meta,
            key_files     => $key_files,
            cloned        => $cloned ? \1 : \0,
        },
        content   => $content,
        truncated => $truncated ? \1 : \0,
    };
}

# Simple JSON encoder fallback
sub _simple_json_encode {
    my ($data) = @_;
    return _encode_value($data);
}

sub _encode_value {
    my ($val) = @_;
    return 'null' unless defined $val;

    my $ref = ref $val;
    if ( !$ref ) {
        if ( $val =~ /^-?\d+$/ && $val !~ /^0\d/ ) {
            return $val;
        }
        $val =~ s/\\/\\\\/g;
        $val =~ s/"/\\"/g;
        $val =~ s/\n/\\n/g;
        $val =~ s/\r/\\r/g;
        $val =~ s/\t/\\t/g;
        return "\"$val\"";
    }
    elsif ( $ref eq 'HASH' ) {
        my @pairs;
        for my $k ( sort keys %$val ) {
            my $ek = $k;
            $ek =~ s/\\/\\\\/g;
            $ek =~ s/"/\\"/g;
            push @pairs, "\"$ek\":" . _encode_value( $val->{$k} );
        }
        return '{' . join( ',', @pairs ) . '}';
    }
    elsif ( $ref eq 'ARRAY' ) {
        return '[' . join( ',', map { _encode_value($_) } @$val ) . ']';
    }
    elsif ( $ref eq 'SCALAR' ) {
        return $$val ? 'true' : 'false';
    }
    else {
        return "\"$val\"";
    }
}

1;

__END__

=head1 NAME

PContext - Library for analyzing and dumping repository context for LLMs

=head1 SYNOPSIS

    use lib 'lib';
    use PContext qw(analyze_repository);

    my $result = analyze_repository({
        path     => '/path/to/repo',
        compress => 1,
    });

    if ($result->{success}) {
        print $result->{content};
    }

=head1 DESCRIPTION

PContext provides functions for analyzing source code repositories and
generating comprehensive, LLM-friendly output. It supports local directories
and remote Git repositories.

=head1 FUNCTIONS

=head2 analyze_repository(\%params)

Main entry point. Analyzes a repository and returns structured results.

Parameters:
    path                  - Local directory path
    git_url               - Git repository URL to clone
    compress              - Boolean, metadata only if true
    output_format         - 'markdown' or 'json'
    include_extensions    - Arrayref of extensions to include
    exclude_patterns      - Arrayref of glob patterns to exclude
    max_file_size         - Max bytes per file
    max_lines_per_chunk   - Lines per chunk (0 = no chunking)
    include_line_numbers  - Boolean, add line numbers
    max_total_output_bytes - Truncate output at this size

Returns hashref with:
    success   - Boolean
    error     - Error details if failed
    metadata  - Repository statistics
    content   - Formatted output
    truncated - Boolean if output was cut

=cut
