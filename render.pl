#!/usr/bin/perl
use strict;
use Cwd;
use File::Basename;
use File::Copy;
use File::Path;
use File::Spec;


######################################################
#### Review and set these variables as appropriate ###
######################################################
my @speeds = ("15", "17", "20", "22", "25", "28", "30", "35", "40", "45", "50");
# my @speeds = ("15/5", "20/10", "25/15");   # Farnsworth 
my $max_processes = 10;
# my $max_processes = 1;
my $test = 0; # 1 = don't render audio -- just show what will be rendered -- useful when encoding text
my $word_limit = -1; # 14 works great... 15 word limit for long sentences; -1 disables it
my $repeat_morse = 1;
my $courtesy_tone = 1;
my $text_to_speech_engine = "neural"; # neural | standard
my $silence_between_morse_code_and_spoken_voice = "1";
my $silence_between_sets = "1"; # typically "1" sec
my $silence_between_voice_and_repeat = "1"; # $silence_between_sets; # typically 1 second
my $extra_word_spacing = 0; # 0 is no extra spacing. 0.5 is half word extra spacing. 1 is twice the word space. 1.5 is 2.5x the word space. etc
my $lang = "ENGLISH"; # ENGLISH | SWEDISH
######################################################
######################################################
######################################################

my $lower_lang_chars_regex = "a-z";
my $upper_lang_chars_regex = "A-Z";
if($lang eq "SWEDISH") {
  $lower_lang_chars_regex = "a-zåäö";
  $upper_lang_chars_regex = "A-ZÄÅÖ";
}

my $cmd;
my @cmdLst;

# text2speech.py error codes (coordinate with text2speech.py error return codes)
my $t2sIOError = 2;

my $filename = File::Spec->rel2abs($ARGV[0]);

print "processing file $filename\n";

my ($file, $dirs, $suffix) = fileparse($filename, qr/\.[^.]*/);
print "dirs: $dirs, file: $file, suffix: $suffix\n";

my $filename_base = File::Spec->catpath("", $dirs, $file);
print "filename base: $filename_base\n";

open my $fh, '<', $filename or die "Can't open file $!";
my $file_content = do { local $/; <$fh> };
close $fh;

my $safe_content = $file_content;
$safe_content =~ s/\s—\s/, /g;
$safe_content =~ s/’/'/g; # replace non-standard single quote with standard one
$safe_content =~ s/\h+/ /g; #extra white space
$safe_content =~ s/(mr|mrs)\./$1/gi;
$safe_content =~ s/!|;/./g; #convert semi-colon and exclamation point to a period
$safe_content =~ s/\.\s+(?=\.)/./g; # turn . . . into ...

if(!$test) {
  print "---- Generating silence and sound effect mp3 files...\n";
  #create silence
  unlink "silence.mp3" if (-f "silence.mp3");
  @cmdLst = ("ffmpeg", "-f", "lavfi", "-i", "anullsrc=channel_layout=5.1:sample_rate=22050", "-t",
             "$silence_between_sets", "-codec:a", "libmp3lame", "-b:a", "256k", "silence.mp3");
  # print("cmd-1: @cmdLst\n");
  system(@cmdLst) == 0 or die "ERROR 1: @cmdLst failed, $!\n";

  # This is the silence between the Morse code and the spoken voice
  unlink "silence1.mp3" if (-f "silence1.mp3");
  @cmdLst = ("ffmpeg", "-f", "lavfi", "-i", "anullsrc=channel_layout=5.1:sample_rate=22050",
             "-t", "$silence_between_morse_code_and_spoken_voice", "-codec:a", "libmp3lame",
             "-b:a", "256k", "silence1.mp3");
  # print "cmd-2: @cmdLst\n";
  system(@cmdLst) == 0 or die "ERROR 2: @cmdLst failed, $!\n";

  # This is the silence between the Morse code and the spoken voice
  unlink 'silence2.mp3' if (-f 'silence2.mp3');
  @cmdLst = ("ffmpeg", "-f", "lavfi", "-i", "anullsrc=channel_layout=5.1:sample_rate=22050",
             "-t", "$silence_between_voice_and_repeat", "-codec:a", "libmp3lame",
             "-b:a", "256k", "silence2.mp3");
  # print "cmd-3: @cmdLst\n";
  system(@cmdLst) == 0 or die "ERROR 3: @cmdLst failed, $!\n";

  #create quieter tone
  unlink 'plink-softer.mp3' if (-f 'plink-softer.mp3');
  $cmd = 'ffmpeg -i sounds/plink.mp3 -filter:a "volume=0.5" plink-softer.mp3';
  # print "cmd-4: $cmd\n";
  system($cmd) == 0 or die "ERROR 4: $cmd failed, $!\n";

  #create quieter tone
  unlink 'pluck-softer.mp3' if (-f 'pluck-softer.mp3');
  $cmd = 'ffmpeg -i sounds/pluck.mp3 -filter:a "volume=0.5" pluck-softer.mp3';
  # print "cmd-5: $cmd\n";
  system($cmd) == 0 or die "ERROR 5: $cmd failed, $!\n";

  if (! -d "cache") {
      mkdir "cache";
  }
}

# Simple string trim function
sub  trim {
  my $s = shift;
  $s =~ s/^\s+|\s+$//g;
  return $s
};

sub split_sentence_by_comma {
  my $sentence = trim($_[0]);
  my @ret = ();
  my $accumulator = "";

  my @sections = split /([^,]+,)/, $sentence;
  foreach(@sections) {
    my $section = trim($_);

    my $accumlator_size = scalar(split /\s+/, $accumulator);
    my $section_size = scalar(split /\s+/, $section);

    if($accumlator_size == 0) {
      $accumulator = trim($section);
    } elsif($word_limit != -1 && ($accumlator_size + $section_size > $word_limit) && ($accumlator_size > 0)) {
      push @ret, $accumulator;
      $accumulator = $section;
    } elsif($section_size > 0) {
      $accumulator = trim($accumulator . ' ' . $section);
    }
    
  }
  push @ret, $accumulator;

  return @ret;
}

sub split_long_section {
  my $sentence = $_[0];

  my $word_count = 0;
  my $partial_sentence = "";
  my @ret = ();
  my @words = split /\s+/, $sentence;
  foreach(@words) {
    my $word = $_;

    $partial_sentence = $partial_sentence . " " . $word;
    $word_count++;
    if($word_limit != -1 && $word_count <= $word_limit) {

    } else {
      push @ret, $partial_sentence;
      $partial_sentence = "";
      $word_count = 0;
    }

  }

  if($word_count > 0) {
    push @ret, $partial_sentence;
  }

  return @ret;
}

sub split_long_sentence {
  my $sentence = $_[0];
  $sentence =~ s/[-]/ /g;
  $sentence =~ s/:/,/g; # makes sense to substitute a colon for a comma
  $sentence =~ s/[^A-Za-z0-9\.\?,'\s]//g;
  my @ret = ();

  my $accumulator = "";

  my @sections = split_sentence_by_comma($sentence);
  foreach(@sections) {
    my $section = $_;

    my @partial_sections = split_long_section($section);
    foreach(@partial_sections) {
      my $partial_section = trim($_);

      my $accumulator_size = scalar(split /\s+/, $accumulator);
      my $partial_section_size = scalar(split /\s+/, $partial_section);

      if($accumulator_size == 0) {
        $accumulator = trim($partial_section);
      } elsif($word_limit != -1 && ($accumulator_size + $partial_section_size > $word_limit) && ($accumulator_size > 0)) {
        push @ret, $accumulator;
        $accumulator = $partial_section; 
      } elsif($partial_section_size > 0) {
        $accumulator = trim($accumulator . ' ' . $partial_section);
      }

    }
  }
  push @ret, $accumulator;

  return @ret;
}

sub split_on_spoken_directive {
  my $raw = $_[0];

  #example "MD MD MD [Maryland|MD]^"
  if($raw =~ m/(.*?)\h*\[(.*?)(\|(.*?))?\]\h*([\^|\.|\?])$/) {
    my $sentence_part = $1.$5;
    my $spoken_directive = $2.$5;
    my $repeat_part = $4.$5;


    $sentence_part =~ s/\^//g;
    $spoken_directive =~ s/\^//g;
    $spoken_directive =~ s/\\\././g; #Unescape period
    $spoken_directive =~ s/\\\?/?/g; #Unescape question mark
    $repeat_part =~ s/\^//g;

    #temporarily change word speed directive so we can filter invalid characters
    $sentence_part =~ s/\|(?=w\d+)/XXXWORDSPEEDXXX/g;
    $repeat_part =~ s/\|(?=w\d+)/XXXWORDSPEEDXXX/g;

    #this should be moved up to safe part.. remember to add ^ and \
    $sentence_part =~ s/[^${upper_lang_chars_regex}${lower_lang_chars_regex}0-9\.\?<>\/,'\s]//g;
    $spoken_directive =~ s/[^${upper_lang_chars_regex}${lower_lang_chars_regex}0-9\.\?<>,'\s]//g;
    $repeat_part =~ s/[^${upper_lang_chars_regex}${lower_lang_chars_regex}0-9\.\?<>\/,'\s]//g;

    #temporarily change word speed directive so we can filter invalid characters
    $sentence_part =~ s/XXXWORDSPEEDXXX/|/g;
    $repeat_part =~ s/XXXWORDSPEEDXXX/|/g;

    if($repeat_part =~ m/^(\.|\?)$/ || $repeat_part eq "") {
      $repeat_part = $sentence_part;
    }

    return ($sentence_part, $spoken_directive, $repeat_part);
  } else {
    #temporarily change word speed directive so we can filter invalid characters

    $raw =~ s/\|(?=w\d+)/XXXWORDSPEEDXXX/g;

    $raw =~ s/\^//g;
    $raw =~ s/[^A-Za-z0-9\.\?<>,'\s]//g;

    $raw =~ s/XXXWORDSPEEDXXX/|/g;

    return ($raw, $raw, $raw);
  }

}

my $punctuation_match = '(?<!\\\\)\.+(?!\w+\.)|(?<!\\\\)\?+|\^'; # Do not match escaped period or question ( \. or \? ) which can be used in spoken directive and don't match things like A.D.
my @sentences = split /($punctuation_match)/, $safe_content;
my $sentence_count = 1;
my $count = 1;
my $is_sentence = 1;
my $sentence;
open(my $fh_all, '>', "$filename_base-sentences.txt");
open(my $fh_structure, '>', "$filename_base-structure.txt");

my $ebookCmd;

foreach(@sentences) {
  my $skip;
  if($is_sentence) {
    $sentence = $_;
    $is_sentence = 0;
    if($sentence =~ m/^\s+$/) {
      $skip = 1;
    } else {
      $sentence_count++;
    }
  } else {
    $is_sentence = 1;

    if($skip == 1) {
      $skip = 0;
      next;
    }

    my $punctuation = $_;

    $sentence = $sentence . $punctuation;
    $sentence =~ s/\n/ /g; #remove extra new lines
    $sentence =~ s/^\s+//g; #remove leading white space
    print $fh_structure "======> $sentence\n";
    print $fh_all "${sentence}\n";

    my($sentence_part, $spoken_directive, $repeat_part) = split_on_spoken_directive($sentence);
    if($word_limit == -1) {
      print "sentence_part: $sentence_part\n";
      print "spoken_directive: $spoken_directive\n";
      print "repeat_part: $repeat_part\n\n";
    }
    if($word_limit != -1 && $sentence_part ne $spoken_directive) {
      print "Error: Cannot have spoken directive with word limit defined!!! Use one or the other!\n";
      print "sentence_part: $sentence_part\n";
      print "spoken_directive: $spoken_directive\n\n";
      exit 1;
    }

    my @partial_sentence = $sentence_part;
    if($word_limit != -1) {
      @partial_sentence = split_long_sentence($sentence);
    }
    foreach(@partial_sentence) {
      print "---- loop 1 - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -\n";
      print "---- debug: partial sentence: $_\n";
            
      my $num_chunks++;
      my $sentence_chunk = $_;

      if($_ !~ m/^\s*$/) {
        print $fh_structure "XXX $sentence_chunk\n";
        if($word_limit != -1) {
          print "sentence and spoken chunk: $sentence_chunk\n";
        }

        if(!$test) {
          $sentence_chunk =~ s/^\s+|\s+$//g; #extra space on the end adds new line!
          open(my $fh, '>', 'sentence.txt');
          print $fh "$sentence_chunk\n";
          close $fh;

          my $counter = sprintf("%05d",$count);
          my $fork_count = 0;
          foreach(@speeds) {
            my $speed = $_;
            my $farnsworth = 0;

            if ($fork_count >= $max_processes) {
              print("XXXXXX Fork 1 xXXXXXXXXXXXXXXXXXXXXXXXxXXXXXXXXXXXXXXXXXXXXXXXxXXXXXXXXXXXXXXXXXXXXXXXxXXXXXXXXXXXX");
              print("XXXXXXxXXXXXXXXXXXXXXXXXXXXXXXxXXXXXXXXXXXXXXXXXXXXXXXxXXXXXXXXXXXXXXXXXXXXXXXxXXXXXXXXXXXX");
              print("waiting on forks: fork_count: $fork_count     max_processes: $max_processes\n");
              wait();
              $fork_count--;
            }

            my $pid = fork();
            die if not defined $pid;
            if($pid) {
              # parent
              $fork_count++;
              print "fork() -- pid: $pid\n";  

            } else {
              #child process
              if($speed =~ m/(\d+)\/(\d+)/) {
                $speed = $1;
                $farnsworth = $2;
              }

              my $rise_and_fall_time;
              my $speed_as_num = int($speed);
              if($speed_as_num < 35) {
                $rise_and_fall_time = 100;
              } elsif($speed_as_num >= 35 && $speed_as_num <= 40) {
                $rise_and_fall_time = 150;
              } else {
                $rise_and_fall_time = 200;
              }

              my $lang_option = "";
              if($lang ne "ENGLISH") {
                $lang_option = "-u";
              }

              my $extra_word_spacing_option = "";
              if ($extra_word_spacing != 0) {
                $extra_word_spacing_option = "-W " . $extra_word_spacing;
              }

              $ebookCmd = "ebook2cw $lang_option -R $rise_and_fall_time -F $rise_and_fall_time " .
                  "$extra_word_spacing_option -f 700 -w $speed -s 44100 ";
              if ($farnsworth != 0) {
                  $ebookCmd = $ebookCmd . "-e $farnsworth ";
              }
              $ebookCmd = $ebookCmd . "-o sentence-${speed} sentence.txt";
              # print "cmd-6: $ebookCmd\n";
              system($ebookCmd) == 0 or die "ERROR 6: $ebookCmd failed, $!\n";

              unlink 'sentence-lower-volume-$speed.mp3' if (-f 'sentence-lower-volume-$speed.mp3');

              $cmd = "ffmpeg -i sentence-${speed}0000.mp3 -filter:a \"volume=0.5\" sentence-lower-volume-${speed}.mp3\n";
              # print "cmd-7: $cmd\n";
              system($cmd) == 0 or die "ERROR 7: $cmd failed, $!\n";
              
              print "---- rename(sentence-lower-volume-${speed}.mp3, $filename_base-$counter-morse-$speed.mp3)\n";
              rename("sentence-lower-volume-$speed.mp3", "$filename_base-$counter-morse-$speed.mp3");

              # generate repeat section if it is different than the sentence
              if($repeat_morse != 0 && $word_limit == -1 && $repeat_part ne $sentence_part) {
                open(my $fh_repeat, '>', 'sentence-repeat.txt');
                print $fh_repeat "$repeat_part\n";
                close $fh_repeat;

                $cmd = "ebook2cw $lang_option -R $rise_and_fall_time -F $rise_and_fall_time $extra_word_spacing_option -f 700 -w $speed -s 44100 -o sentence-repeat-${speed} ";
                if ($farnsworth > 0) {
                  $cmd = $cmd . "-e $farnsworth ";
                }
                $cmd = $cmd . "sentence-repeat.txt";
                # print "cmd-8: $cmd\n";
                system($cmd) == 0 or die "ERROR 8: $cmd failed, $!\n";

                unlink 'sentence-repeat-lower-volume-$speed.mp3' if (-f 'sentence-repeat-lower-volume-$speed.mp3');

                $cmd = sprintf('ffmpeg -i sentence-repeat-%d0000.mp3 -filter:a "volume=0.5" sentence-repeat-lower-volume-%d.mp3', $speed, $speed);
                # print "cmd-9: $cmd\n";
                system($cmd);
                if ($? == -1) {
                    print "ERROR: cmd: $cmd failed to execute: $!\n";
                    exit 9;
                }
                elsif ($? & 127) {
                    printf "cmd: $cmd died with signal %d, %s coredump\n",
                        ($? & 127), ($? & 128) ? 'with' : 'without';
                    exit 9;
                }
                else {
                    my $ecode = $? >> 8;
                    if ($ecode != 0) {
                        printf "ERROR cmd: $cmd unsuccessful: $!\n";
                        exit 9;
                    }
                }
                
                move("sentence-repeat-lower-volume-${speed}.mp3", "$filename_base-$counter-repeat-morse-$speed.mp3");

              }   # repeat morse if clause

              exit;

            }   # child process
          }  # foreach(@speeds)

          for (1 .. $fork_count) {
            wait();
          }

          # Generate spoken section
          if($word_limit != -1) {
              rename('sentence.txt', '$filename_base-$counter.txt');
          } else {
            open(my $fh_spoken, '>', "$filename_base-$counter.txt");
            print $fh_spoken "$spoken_directive\n";
            close $fh_spoken;
          }

          my $exit_code = -1;
          while($exit_code != 0) {
            my $textFile = File::Spec->rel2abs("$filename_base-${counter}");
              
            print "execute text2speech.py: \"$textFile\" $text_to_speech_engine $lang\n";
              
            $exit_code = system("./text2speech.py \"$textFile\" $text_to_speech_engine $lang");
            if ($? == -1) {
                print "ERROR: text2speech.py failed to execute: $!\n";
                exit 1;
            }
            elsif ($? & 127) {
                printf "text2speech.py died with signal %d, %s coredump\n",
                    ($? & 127), ($? & 128) ? 'with' : 'without';
                exit 1;
            }
            else {
                my $ecode = $? >> 8;
                printf "text2speech.py exited with value %d\n", $ecode;

                if ($ecode == 1) {
                    print "text2speech.py exit_code: $exit_code\n";
                    exit 1;
                }
                elsif ($ecode == $t2sIOError) {
                    print "ERROR: text2speech.py error reading aws.properties file\n";
                    exit 1;
                }
            }
          }
        }
        $count++;
      }
    }    # foreach(@partial_sentence)

    if(scalar(@partial_sentence) > 1) {
      print "saying the whole sentence: $sentence\n";

      if(!$test) {
        open(my $fh, '>', 'sentence.txt');
        print $fh "$sentence\n";

        my $counter = sprintf("%05d",$count);
        rename('sentence.txt ', '$filename_base-$counter-full.txt');
        my $exit_code = -1;
        while($exit_code != 0) {
          $exit_code = system('./text2speech.py '."$filename_base-${counter}-full $text_to_speech_engine $lang");
        }

        $count++;

        close $fh;
      }
    }

  }
}      # foreach(@sentences)
################
###############
close $fh_all;
close $fh_structure;
$count--;

print "\n\nTotal sentences: $sentence_count\t segments: $count\n";
if(!$test) {
  my $cwd = getcwd();

  #lame documentation -- https://svn.code.sf.net/p/lame/svn/trunk/lame/USAGE
  unlink "$cwd/silence-resampled.mp3";
  my $cmd = "lame --resample 44.1 -a -b 256 $cwd/silence.mp3 $cwd/silence-resampled.mp3";
  # print "cmd-10: $cmd\n";
  system($cmd) == 0 or die "ERROR 10: $cmd failed, $!\n";

  unlink "$cwd/silence-resampled1.mp3";
  $cmd = "lame --resample 44.1 -a -b 256 $cwd/silence1.mp3 $cwd/silence-resampled1.mp3";
  # print "cmd-11: $cmd\n";
  system($cmd) == 0 or die "ERROR 11: $cmd failed, $!\n";;

  unlink "$cwd/silence-resampled2.mp3";
  $cmd = "lame --resample 44.1 -a -b 256 $cwd/silence2.mp3 $cwd/silence-resampled2.mp3";
  # print "cmd-12: $cmd\n";
  system($cmd) == 0 or die "ERROR 12: $cmd failed, $!\n";;

  unlink "$cwd/pluck-softer-resampled.mp3";
  $cmd = "lame --resample 44.1 -a -b 256 $cwd/pluck-softer.mp3 $cwd/pluck-softer-resampled.mp3";
  # print "cmd-13: $cmd\n";
  system($cmd) == 0 or die "ERROR 13: $cmd failed, $!\n";;

  unlink "$cwd/plink-softer-resampled.mp3";
  $cmd = "lame --resample 44.1 -a -b 256 $cwd/plink-softer.mp3 $cwd/plink-softer-resampled.mp3";
  # print "cmd-14: $cmd\n";
  system($cmd) == 0 or die "ERROR 14: $cmd failed, $!\n";;

  my $fork_count = 0;
  foreach(@speeds) {
    my $first_for_given_speed = 1;
    my $speed_in = $_;

    my $speed;
    if($speed_in =~ m/(\d+)\/\d+/) {
      $speed = $1;
    } else {
      $speed = $speed_in;
    }

    if($fork_count >= $max_processes) {
      print("XXXXXX Fork 2 xXXXXXXXXXXXXXXXXXXXXXXXxXXXXXXXXXXXXXXXXXXXXXXXxXXXXXXXXXXXXXXXXXXXXXXXxXXXXXXXXXXXXXXXXXXXXXXXxXXXXXXXXXXXXXXXXX\n");
      print("XXXXXXxXXXXXXXXXXXXXXXXXXXXXXXxXXXXXXXXXXXXXXXXXXXXXXXxXXXXXXXXXXXXXXXXXXXXXXXxXXXXXXXXXXXXXXXXXXXXXXXxXXXXXXXXXXXXXXXXX\n");
      print("waiting on forks: fork_count: $fork_count     max_processes: $max_processes\n");
      wait();
      $fork_count--;
    }

    my $pid = fork();
    die if not defined $pid;
    if($pid) {
      # parent
      $fork_count++;

    } else {
      unlink "$filename_base-${speed}wpm.mp3";

      open(my $fh_list, '>', "$filename_base-list-${speed}wpm.txt");
      for (my $i=1; $i <= $count; $i++) {
        my $counter = sprintf("%05d",$i);

        #if full sentence
        if(-e "$filename_base-$counter-full-voice.mp3") {
          print $fh_list "file '$cwd/pluck-softer-resampled.mp3'\nfile '$cwd/silence-resampled.mp3'\nfile '$filename_base-$counter-full-voice-resampled-$speed.mp3'\nfile '$cwd/silence-resampled.mp3'\n";

          @cmdLst = ('lame', '--resample', '44.1', '-a', '-b', '256', "$filename_base-$counter-full-voice.mp3", "$filename_base-$counter-full-voice-resampled-$speed.mp3");
          # print "cmdLst-15:\n";
          foreach (@cmdLst) {
              print "-- $_\n";
          }
          # print "cmd-16: @cmdLst\n";
          system(@cmdLst) == 0 or die "ERROR 16: @cmdLst failed, $!\n";

        } else {
          # Not full sentence\n";
          if($first_for_given_speed == 1) {
            $first_for_given_speed = 0;
          } elsif ($courtesy_tone != 0) {
            print $fh_list "file '$cwd/plink-softer-resampled.mp3'\n";
          }

          @cmdLst = ("lame", "--resample", "44.1", "-a", "-b", "256",
                     "$filename_base-$counter-morse-$speed.mp3",
                     "$filename_base-$counter-morse-$speed-resampled.mp3");
          # print "cmdLst-16: @cmdLst\n";
          system(@cmdLst) == 0 or die "ERROR: @cmdLst failed, $!\n";

          @cmdLst = ("lame", "--resample", "44.1", "-a", "-b", "256",
                     "$filename_base-$counter-voice.mp3",
                     "$filename_base-$counter-voice-resampled-$speed.mp3");
          # print "cmd-17: @cmdLst\n";
          system(@cmdLst) == 0 or die "ERROR 17: @cmdLst failed, $!\n";

          print $fh_list "file '$cwd/silence-resampled.mp3'\nfile '$filename_base-$counter-morse-$speed-resampled.mp3'\nfile '$cwd/silence-resampled1.mp3'\nfile '$filename_base-$counter-voice-resampled-$speed.mp3'\n";

          if($repeat_morse == 0) {
            print $fh_list "file '$cwd/silence-resampled.mp3'\n";
          } else {
            print $fh_list "file '$cwd/silence-resampled2.mp3'\n";
            if (-e "$filename_base-$counter-repeat-morse-$speed.mp3") {
              @cmdLst = ("lame", "--resample", "44.1", "-a", "-b", "256",
                         "$filename_base-$counter-repeat-morse-$speed.mp3",
                         "$filename_base-$counter-repeat-morse-$speed-resampled.mp3");
              # print "cmd-18: @cmdLst\n";
              system(@cmdLst) == 0 or die "ERROR 18: @cmdLst failed, $!\n";

              print $fh_list "file '$filename_base-$counter-repeat-morse-$speed-resampled.mp3'\nfile '$cwd/silence-resampled.mp3'\n";

            } else {

              print $fh_list "file '$filename_base-$counter-morse-$speed-resampled.mp3'\nfile '$cwd/silence-resampled.mp3'\n";
            }
          }


        }
      }
      close $fh_list;
      #see -- https://superuser.com/questions/314239/how-to-join-merge-many-mp3-files  or   https://trac.ffmpeg.org/wiki/Concatenate
      @cmdLst = ("ffmpeg", "-f", "concat", "-safe", "0", "-i", 
                 "$filename_base-list-${speed}wpm.txt", "-codec:a", "libmp3lame", "-metadata",
                 "title=\"$filename_base $speed"."wpm\"", "-c", "copy",
                 "$filename_base-$speed"."wpm.mp3");
      # print "cmd-19: @cmdLst\n";
      system(@cmdLst) == 0 or die "ERROR 19: @cmdLst failed, $!\n";

      exit;
    }
    # end of fork

  }     # foreach(@speeds)

  for (1 .. $fork_count) {
    wait();
  }

  #remove temporary files
  print "Clean up temporary files...\n";
  
  for (my $i=1; $i <= $count; $i++) {
    my $counter = sprintf("%05d",$i);
    unlink glob("'$filename_base-$counter-*.mp3'");
    unlink glob("'$filename_base-$counter.txt'");
  }

  my $speed;
  foreach(@speeds) {
    if ($_ =~ m/(\d+)\//) {
        $speed = $1;
    }
    else {
        $speed = $_;
    }
    unlink "sentence-${speed}0000.mp3", "sentence-repeat-${speed}0000.mp3",  "$filename_base-list-${speed}wpm.txt", "silence.mp3";
  }
  unlink "$filename_base-structure.txt", "$filename_base-sentences.txt";
  unlink glob("silence*.mp3");
  unlink glob("pluck*.mp3");
  unlink glob("plink*.mp3");
  unlink "sentence.txt";
  unlink "sentence-repeat.txt";
}