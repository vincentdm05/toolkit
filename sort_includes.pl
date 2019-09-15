#!/usr/bin/env perl

use File::Find;
use File::Spec::Functions;
use strict;
use warnings;

my $ignoreCase = 0;
my $verbose = 0;
my $recurse = 0;
my @dirs = ();
my @filenames = ();

read_args();
find_files();
sort_includes($_) foreach (@filenames);

sub println_if_v
{
	print "@_\n" if $verbose;
}

sub warnln_if_v
{
	warn "@_\n" if $verbose;
}

sub read_args
{
	foreach my $arg (@ARGV)
	{
		# Regex explanation:
		# ^ : beginning of line (since each $arg is a single line, this is the start of the sequence)
		# - : match character '-'
		# (?! : begin non-capturing negative lookahead group
		# .* : any character except '\n' any number of times (including 0)
		# (.) : 1st captured any character except '\n', exactly once
		# \1 : repetition of 1st captured group
		# (?!.*(.).*\1.*) : must not match any sequence of non-'\n' characters where one is repeated
		# [ivr]+ : either of the characters in the set at least once
		# $ : end of line
		# In summary: all combinations of characters from the set [vr] (without repetition)
		# It would be easier not to enforce non-repetition (^-[vr]+$) but what's the fun?
		if ($arg =~ /^-(?!.*(.).*\1.*)[ivr]+$/)
		{
			if ($arg =~ /i/)
			{
				$ignoreCase = 1;
			}
			if ($arg =~ /r/)
			{
				$recurse = 1;
			}
			if ($arg =~ /v/)
			{
				$verbose = 1;
			}
			next;
		}
		if (-d $arg)
		{
			push @dirs, $arg;
			next;
		}
		my $filename = catfile(".", $arg);
		if (match_file($filename))
		{
			push @filenames, $filename;
			next;
		}
		warnln_if_v("Unrecognized input \'$arg\' will be ignored.");
	}
}

sub find_files
{
	if ($recurse)
	{
		find(\&found_file, @dirs);
	}
	else
	{
		foreach my $dir (@dirs)
		{
			if (opendir(my $dh, $dir))
			{
				while (readdir($dh))
				{
					my $filename = catfile($dir, $_);
					if (match_file($filename))
					{
						push @filenames, $filename;
					}
				}
				closedir($dh) or warnln_if_v("Directory closing failed: $!");
			}
			else
			{
				warnln_if_v("Cannot open directory \'$dir\'");
			}
		}
	}
	@filenames = uniq(@filenames);
}

# Matches a single parameter with file format
sub match_file
{
	my ($file) = @_;
	# Note: A character is causing trouble with syntax highlighting, hence the end-of-line comment
	-f $file && $file =~ /^[^\\\/:*?"<>|]+\.[ch](pp)?$/;	#"
}

# Handle files found with find()
sub found_file
{
	# Assuming find was called with chdir enabled
	if (match_file($_))
	{
		my $relpath = $File::Find::name;
		# Remove leading ./
		$relpath =~ s/^\.\///;
		# TODO: directly handle file without storing, but can't uniq anymore
		push @filenames, $relpath;
	}
}

# Matches a single parameter with include format
sub match_include
{
	my ($arg) = @_;
	$arg =~ /^\s*\#include\s+[<"]/;
}

sub uniq
{
	my %seen;
	# For each element of @_, namely $_, use it as key to the %seen hash table and get its value.
	# If it doesn't exist yet, the value is 0, resulting in a truth value of 'true', and finally
	# incremented by one. The evaluation of the inner expression results in the yielding (or not)
	# of each evaluated item, producing an array of unique elements of @_.
	grep !$seen{$_}++, @_;
}

# Sorts include list alphabetically, ignoring leading whitespaces.
# A special marker is added at the end of the returned array, indicating change.
sub sort_ignore_leading_whitespace
{
	my $changed = 0;
	my @list = @_;
	# To understand, read backwards:
	# First, map all indices from the input array to their corresponding element as well as their
	# corresponding no-leading-whitespace equivalent.
	# Then sort that array using the last element, and mark as changed when necessary.
	# Finally, map back to the original string.
	# Also add change marker at the end of returned array.
	my @sorted = map
	{
		$_->[1]
	}
	sort
	{
		my $res;
		if ($ignoreCase)
		{
			$res = lc $a->[2] cmp lc $b->[2];
		}
		else
		{
			$res = $a->[2] cmp $b->[2];
		}
		if ($res == 1 && $a->[0] < $b->[0])
		{
			$changed += 1;
		}
		$res
	}
	map
	{
		my $index = $_;
		my $value = $list[$index];
		[$index, $value, $value =~ /\#include\s+[<"]([^>"])+[>"]/]
	} 0 .. $#list;
	push @sorted, $changed;
	return @sorted;
}

# This is the core subroutine, taking a file name as argument, reading the file, sorting
# consecutive lines of includes and writing back if there was a change.
sub sort_includes
{
	my ($file) = @_;
	my $fh;
	if (!open($fh, '+<', $file))
	{
		warnln_if_v("Could not open \'$file\'");
		return;
	}

	# TODO: make comments 'stick' to the following line
	# (idea: use a hash with line as key and comment(s) as value)
	my @lines = ();
	my @includes = ();
	my $changed = 0;
	while (my $line = <$fh>)
	{
		if (match_include($line))
		{
			push @includes, $line;
		}
		else
		{
			if (@includes > 1)
			{
				my @sorted = sort_ignore_leading_whitespace(uniq(@includes));
				$changed += pop @sorted;
				@includes = @sorted;
			}
			push @lines, @includes if @includes;
			push @lines, $line;
			@includes = ();
		}
	}

	if (@includes > 1)
	{
		my @sorted = sort_ignore_leading_whitespace(uniq(@includes));
		$changed += pop @sorted;
		@includes = @sorted;
	}
	push @lines, @includes if @includes;

	if ($changed)
	{
		println_if_v("Sorted includes for \'$file\'");
		# Go back to start of file
		seek $fh, 0, 0;
		# Erase the file
		truncate $fh, 0;
		# Rewrite content
		print $fh @lines;
	}

	close($fh) or warnln_if_v("Close failed: $!");
}
