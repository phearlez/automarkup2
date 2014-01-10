#!/usr/bin/env perl
use strict;
use LWP;
use HTTP::Cookies;
use Time::localtime;
use Text::CSV;
use JSON;
#my $json = JSON->new;
use List::MoreUtils 'any';
use File::Slurp;

# use HTML::TokeParser;
# use URI::Escape;
# use URI;
use Cwd;
use lib cwd();

use DateTime;
use DateTime::Format::XSD;

my $path = `pwd`;
chomp($path);

use Data::Dumper;
$Data::Dumper::Indent = 1;

my $logincredentials = [
				'login' => 'REDACTED',
				'password' => 'REDACTED'
			];

my $logging = 1;
my $debug = 0;
my $skip_download = 0;
my $skip_process = 0;
my $skip_posting = 1;

my $types_to_match = "usc,stat,law"; #,law

my $baseURL = "http://deepbills.dancingmammoth.com";
# internal use only
# if ($debug) {
# 	$baseURL = "http://127.0.0.1:6543"
# }
my $loginURI = $baseURL."/login";
my $listURI = $baseURL."/dashboard/?format=csv";
my $getURI = $baseURL."/bills/";
my $postURI = $getURI; #it's the same! Just POST instead!

my $ua = LWP::UserAgent->new();

	#we'll skip getting new files if we're still debugging
	if (! $skip_download) {

		my $listing = $ua->get($listURI);

		open my $fh, '<', \$listing->content or die $!;
		my $csv = Text::CSV->new({ sep_char => ',' });
		#Let's get all the files... but first we need to remove the old ones
		opendir(DIR, $path);
		my @files = grep { /\.(xml)$/ } readdir(DIR);
		closedir(DIR);
		#let's unlink every XML file to clear out and make sure we have current stuff
		foreach (@files) {
			unlink($_)
		}
		if ($listing->is_success) {
			while (my $row = $csv->getline($fh)) {
	#			if (@$row[5] =~ /auto-markup|new/) {
				if (@$row[5] =~ /new/) {
					print "Mirroring ", @$row[5], " document ", @$row[0], "\n";
					#get all the files!
					my $eachFile = $ua->mirror($getURI.@$row[0], @$row[0].".xml");
					if ($eachFile->is_error) {
						print "Retrieval failed: ", $eachFile->status_line, "\n" ;
						next;
					}
				}
			}
		} else {
 			die "Unable to get documents from server, ", $listing->status_line;
		}
	}

	if (! $skip_process) {
		#Okay, now we have as many files as we're going to have. Let's process them
	
		#first up, garbage collection; ditch the supporting files
		opendir(DIR, $path);
		my @files = grep { /\.(new|debug)$/ } readdir(DIR);
		closedir(DIR);	
		foreach (@files) {
			unlink($_)
		}	
	
		opendir(DIR, $path);
		@files = grep { /\.xml$/ } readdir(DIR);
		closedir(DIR);
		foreach my $process_this_file (@files) {
			print "Processing $process_this_file... ";
			#Load up the citation parser and create a .json file with the results
			`cite -t $types_to_match -i $process_this_file -o $process_this_file.json`;
			#load up the contents of that file
			my $citations = read_file("$process_this_file.json");
			my $citelist = decode_json $citations;
			my $citearray = $citelist->{'citations'};
			
			if ($debug) {
				open(SAVEDEBUG, ">", $process_this_file.'.cites.decoded.debug')
			         or die "can't open $process_this_file.cites.raw.debug: $!\n";
			    foreach (@{$citearray}) {
			        print SAVEDEBUG Dumper($_);
			    }
			    close(SAVEDEBUG); 
			}
	
			my $original_file = read_file($process_this_file, binmode => ':utf8');
			my $original_file_len = length $original_file;
	
			#we're creating a sequence of slices of the original document here; they will either be unchanged chunks where no items were found or they'll be transformed sections where a citation was discovered and additonal tags applied. Later we're reassemble them into the final document.
			my (@slice_start, @slice_len, @slice_new_text) = ();
			my $matchindex = -1;
			foreach my $eachCite (@{$citearray}) {
				#we don't care about CFR or the DC codes found by this tool
				#in theory only the three we explicitly requested will come through but hey, suspenders and belt right?
				if ($eachCite->{'type'} =~ /law|usc|stat/) {
					my $lastmatchindex = $matchindex;
					$matchindex = $eachCite->{'index'};
					#cite at this moment has a bug which will return multiple finds for a single index in the location
					#since we do not tag that way we only match the first which, as it stands, is the most rich of the finds
					if ($matchindex > $lastmatchindex) {
						my $matchtext = $eachCite->{'match'};
						my $matchtype = $eachCite->{'type'};
						my $matchcite = $eachCite->{$matchtype}->{'id'};
						my $entitytype;

						if ($eachCite->{'type'} =~ /law/) {
							$matchcite =~ s|^us-law/public|public-law|;
							$entitytype = 'public-law';
						}
						if ($eachCite->{'type'} =~ /stat/) {
							$matchcite =~ s/^stat/statute-at-large/;
							$entitytype = 'statute-at-large';
						}				
						if ($eachCite->{'type'} =~ /usc/) {
							$entitytype = 'uscode';
							#the cite app labels things with an et-seq but our syntax uses etseq, so we need to transform that
							$matchcite =~ s/et-seq/etseq/;						
							#the cite app treats appendix finds in an identical way to standard but we do something different
							#here we'll change the type of tag we use to the proper appendix tag as well as removing the -app from the first level find
							if ($matchcite =~ /-app\//) {
								# remove the -app and turn the first part from usc to usc-appendix
								$matchcite =~ s/^usc/usc-appendix/;
								$matchcite =~ s/(\d)-app\//$1\//;
							}
						}

						# if we're not picking up exactly where we left off then we need to create an indication
						# to pull that unused string forward
						if (scalar @slice_start) {
							#there's been at least one find; build something to slice that unchanged text (if any)
								push @slice_start, $slice_start[$#slice_start]+$slice_len[$#slice_start];
								push @slice_len,  $matchindex - $slice_start[$#slice_start];					
								push @slice_new_text, '';
						} else { #nothing in the array yet
							if ($matchindex > 0) { #VERY remotely possible we match at very first char, in which case this is unneeded
								push @slice_start, 0;
								push @slice_len, $matchindex;
								push @slice_new_text, '';
							}
						}

						push @slice_start, $eachCite->{'index'};
						push @slice_len, length($matchtext);
						push @slice_new_text, "<cato:entity-ref xmlns:cato=\"http://namespaces.cato.org/catoxml\" entity-type=\"$entitytype\" value=\"$matchcite\">$matchtext</cato:entity-ref>";
					} else {
						$debug and print DEBUG "DUPE HIT, SKIPPING\n";
					}
				}
			} #done looping the cites
	
			# build the last splicer block (if needed)
			if (scalar @slice_start) {
				#there's been at least one find; let's build the last slice as needed
				if (($slice_start[$#slice_start]+$slice_len[$#slice_len]) < $original_file_len-1) {
					push @slice_start, $slice_start[$#slice_start]+$slice_len[$#slice_len];
					push @slice_len,  $original_file_len;					
					push @slice_new_text, '';
				}
			}
	
			if ($debug) {
				open(SAVEDEBUG, ">", $process_this_file.'.substitutions.debug')
		            	or die "can't open $process_this_file.substitutions.debug: $!";
		    	$debug and print SAVEDEBUG  "Original file length ". $original_file_len . "\n";
			}	

			my $hitcount = scalar @slice_start;
			if ($hitcount) {
		    	$debug and print SAVEDEBUG  "$hitcount items to splice\n";
	
				my $new_file ='';
				#new good style
				foreach (0..$#slice_start) {
		        	$debug and print SAVEDEBUG $slice_start[$_] . " through " . ($slice_start[$_]+$slice_len[$_])." ";
		        	
					if (length $slice_new_text[$_]) {
						#we're doing a substitution
						$new_file .= $slice_new_text[$_];							
			        	$debug and print SAVEDEBUG  "substitution\n";
					} else {
						#this is a straight-up no change section
						$new_file .= substr($original_file, $slice_start[$_], $slice_len[$_]);
			        	$debug and print SAVEDEBUG  "copying $slice_len[$_] characters starting at $slice_start[$_]\n";
					}
				}				
		        write_file($process_this_file.'.new', {binmode => ':utf8'}, $new_file);
			} else {
				print "\tno matches found, nothing to do!\n";
			}
	
			if ($debug) {
				close(SAVEDEBUG); 
			}	
			print "\n";
		}
	} #end if (! $skip_process)

	if (! $skip_posting) {
		opendir(DIR, $path);
		my @files = grep { /\.new$/ } readdir(DIR);
		closedir(DIR);

		#site uses cookies for authentication. We don't need to store it after script 
		#ending but we do need it to persist between queries
		my $cookie_jar = HTTP::Cookies->new();
		$ua->cookie_jar($cookie_jar);
		my $response = $ua->post(
			$loginURI,
			$logincredentials
			);
		#No point in continuing if we can't connect in order to authenticate.
		$logging and (print "***** Post login response: ".$response->status_line . "\n");
		#**sigh** the 303 redirect doesn't live up to 'success' so we're going to explicitly stop only on error
		die "Error on login: ", $response->status_line if $response->is_error;

		foreach my $process_this_file (@files) {
			my $save_file_name = substr($process_this_file, 0, -8);
			print "Time to post $save_file_name\n";
			my $submitURL = "$postURI$save_file_name/edit";
			print "Posting to $submitURL\n";
	#		print "Upload file ". $_ . "\n";
			#committer, time, status=, description=, text =
			my $dt = DateTime->now;
			my $markeduptext = read_file("$process_this_file");
			my $response = $ua->post( $submitURL, { 'status'=> 'auto-markup2', 'description' => 'automarkupv2', 'text' => $markeduptext } );
			my $content  = $response->decoded_content();		
			print "Post result: $content\n";

		}
	}