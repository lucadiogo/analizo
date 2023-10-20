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
  my ($self, $doxyparse_output, $line) = @_;
  my $yaml = undef;

  # eval { $yaml = Load($doxyparse_output) };

  if ($@) {
    die $!;
  }

  # print "\n$doxyparse_output\n";

  my @lines = split(/\n/, $doxyparse_output);

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
      }
      elsif ($type2 =~ /Attribute/) {
        my $function = $node1;
        my $variable = $node2;
      
        $self->model->declare_variable($function, $variable);
      }
    }


    $i += 1;
  }

  foreach my $full_filename (sort keys %$yaml) {

    # current file declaration
    my $file = _strip_current_directory($full_filename);
    $self->current_file($file);
    $self->_add_file($file);

    # current module declaration
    foreach my $module (keys %{$yaml->{$full_filename}}) {
      my $modulename = _file_to_module($module);
      next if defined $yaml->{$full_filename}->{$module} && ref($yaml->{$full_filename}->{$module}) ne 'HASH';

      $self->current_module($modulename);
      $self->_cpp_hack($modulename);

      # inheritance
      if (defined $yaml->{$full_filename}->{$module}->{inherits}) {
        if (ref $yaml->{$full_filename}->{$module}->{inherits} eq 'ARRAY') {
          foreach my $inherits (@{ $yaml->{$full_filename}->{$module}->{inherits} }) {
            $self->model->add_inheritance($self->current_module, $inherits);
          }
        }
        else {
          my $inherits = $yaml->{$full_filename}->{$module}->{inherits};
          $self->model->add_inheritance($self->current_module, $inherits);
        }
      }

      # abstract class
      if (defined $yaml->{$full_filename}->{$module}->{information}) {
        if ($yaml->{$full_filename}->{$module}->{information} eq 'abstract class') {
          $self->model->add_abstract_class($self->current_module);
        }
      }

      foreach my $definition (@{$yaml->{$full_filename}->{$module}->{defines}}) {
        my ($name) = keys %$definition;
        next if $definition->{$name}->{prototype} and $definition->{$name}->{prototype} eq 'yes';
        my $type = $definition->{$name}->{type};
        my $qualified_name = _qualified_name($self->current_module, $name);
        $self->{current_member} = $qualified_name;

        # function declarations
        if ($type eq 'function') {
          $self->model->declare_function($self->current_module, $qualified_name);
        }
        # variable declarations
        elsif ($type eq 'variable') {
          $self->model->declare_variable($self->current_module, $qualified_name);
        }
        #FIXME: Implement define treatment (no novo doxyparse identifica como type = "macro definition")
        # define declarations
        elsif ($type eq 'macro definition') {
          #$self->{current_member} = $qualified_name;
        }

        # public members
        if (defined $definition->{$name}->{protection}) {
          my $protection = $definition->{$name}->{protection};
          $self->model->add_protection($self->current_member, $protection);
        }

        # method LOC
        if (defined $definition->{$name}->{lines_of_code}) {
          $self->model->add_loc($self->current_member, $definition->{$name}->{lines_of_code});
        }

        # method parameters
        if (defined $definition->{$name}->{parameters}) {
          $self->model->add_parameters($self->current_member, $definition->{$name}->{parameters});
        }

        # method conditional paths
        if (defined $definition->{$name}->{conditional_paths}) {
          $self->model->add_conditional_paths($self->current_member, $definition->{$name}->{conditional_paths});
        }

        foreach my $uses (@{ $definition->{$name}->{uses} }) {
          my ($uses_name) = keys %$uses;
          my $uses_type = $uses->{$uses_name}->{type};
          my $defined_in = $uses->{$uses_name}->{defined_in};
          my $qualified_uses_name = _qualified_name($defined_in, $uses_name);
          # function calls/uses
          if ($uses_type eq 'function') {
            $self->model->add_call($self->current_member, $qualified_uses_name, 'direct');
          }
          # variable references
          elsif ($uses_type eq 'variable') {
            $self->model->add_variable_use($self->current_member, $qualified_uses_name);
          }

        }
      }
    }
  }
  # print Dumper $self->model;
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

    open PYAN, "pyan3 --uses --inherits --defines --grouped --annotated --tgf \$(cat $temp_filename) --log ../loggg |" or die "can't run pyan: $!";

    local $/ = undef;
    my $doxyparse_output = <PYAN>;
    close PYAN or die "doxyparse error";
    $self->feed($doxyparse_output);
    unlink $temp_filename;
  };
  if($@) {
    warn($@);
    exit -1;
  }
}

1;