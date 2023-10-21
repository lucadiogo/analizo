package Analizo::Extractor::Pyan;

use strict;
use warnings;

use parent qw(Analizo::Extractor);

use File::Temp qw/ tempfile /;
use Cwd;
use YAML::XS;
use File::Spec::Functions qw/ tmpdir /;
use Data::Dumper;

sub new {
  my ($package, @options) = @_;
  return bless { files => [], @options }, $package;
}

sub _add_file {
  my ($self, $file) = @_;
  push(@{$self->{files}}, $file);
}


sub feed {
  my ($self, $pyan_output, $line) = @_;
  my $yaml = undef;

  # eval { $yaml = Load($pyan_output) };

  if ($@) {
    die $!;
  }

  # print "\n$pyan_output\n";

  my @lines = split(/\n/, $pyan_output);

  # my @declarations = map { $_ } @lines;

  my $i = 0;

  my %id_to_class = ();



  while ($lines[$i] !~ /#/) {
    my @values = split(/ /, $lines[$i]);

  # if ($values[1] =~ /.*\\n.*/) {
    $values[1] =~ s/\\n.*//;
    $id_to_class{$values[0]} = ($values[1]);


    # $self->_add_file("Arquivo");



    if ($values[1] =~ s/Module://) {
      $self->model->declare_module($values[1], $values[1]);
    }

    if ($values[2] =~ /abstractclass/) {
      # print "ABS: $values[1]\n";
      $self->model->add_abstract_class($values[1])
    }

    $i += 1;
  }


  $i += 1;

  while ($i < scalar(@lines)) {
    my @values = split(/ /, $lines[$i]);

    # print $id_to_class{$values[0]} . " " . $id_to_class{$values[1]} . "\n";
    my ($node1, $type1) = sanitize_input($id_to_class{$values[0]});
    my ($node2, $type2) = sanitize_input($id_to_class{$values[1]});



    my $relation = $values[2];

    if ($relation =~ /U/) {
      
      if ($type2 =~ /FunctionDef/) {
      my $class = $node1;
      my $function = $node2;
        $self->model->add_call($class, $function, 'direct');
      }
      elsif ($type2 =~ /Attribute/) {
        my $function = $node1;
        my $variable = $node2;
        $self->model->add_variable_use($function, $variable, 'direct');
      }
    }
    elsif ($relation =~ /I/) {
      my $class = $node1;
      my $who = $node2;
      $self->model->add_inheritance($class, $who);

      # $self->model->add_call("$class", "$who", 'direct');

    }
    elsif ($relation =~ /D/) {


      if ($type2 =~ /FunctionDef/) {
        my $class = $node1;
        my $function = $node2;
        $self->model->declare_function($class, $function);

        $self->model->add_protection($function, "public");
        $self->model->add_loc($function, 1);
        $self->model->add_parameters($function, 0);
        $self->model->add_conditional_paths($function, 1);

      }
      elsif ($type2 =~ /Attribute/) {
        my $function = $node1;
        my $variable = $node2;
      
        $self->model->declare_variable($function, $variable);
      }
    }


    $i += 1;
  }

  print Dumper $self->model;
} 

sub sanitize_input {
  my ($input) = @_;

  my ($type, $name) = split(/->/, $input);

  return ($name, $type);

}

# concat module with symbol (e.g. main::to_string)
sub _qualified_name {
  my ($file, $symbol) = @_;
  _file_to_module($file) . '::' . $symbol;
}

# discard file suffix (e.g. .c or .h)
sub _file_to_module {
  my ($filename) = @_;
  $filename ||= 'unknown';
  $filename =~ s/\.\w+$//;
  return $filename;
}

sub _strip_current_directory {
  my ($file) = @_;
  my $pwd = getcwd();
  $file =~ s#^$pwd/##;
  return $file;
}

sub actually_process {
  my ($self, @input_files) = @_;
  my ($temp_handle, $temp_filename) = tempfile();
  foreach my $input_file (@input_files) {
    print $temp_handle "$input_file\n"
  }
  close $temp_handle;

  eval 'use Alien::Doxyparse';
  $ENV{PATH} = join(':', $ENV{PATH}, Alien::Doxyparse->bin_dir) unless $@;

  eval {
    local $ENV{TEMP} = tmpdir();
    # open DOXYPARSE, "doxyparse - < $temp_filename |" or die "can't run doxyparse: $!";

    open PYAN, "pyan3 --uses --inherits --defines --grouped --annotated --tgf \$(cat $temp_filename) |" or die "can't run pyan: $!";

    local $/ = undef;
    my $pyan_output = <PYAN>;
    close PYAN or die "doxyparse error";
    $self->feed($pyan_output);
    unlink $temp_filename;
  };
  if($@) {
    warn($@);
    exit -1;
  }
}

1;
