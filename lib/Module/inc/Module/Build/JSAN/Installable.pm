#line 1
package Module::Build::JSAN::Installable;

use strict;
use vars qw($VERSION @ISA);

$VERSION = '0.09';

use Module::Build::JSAN;
@ISA = qw(Module::Build::JSAN);

use File::Spec::Functions qw(catdir catfile);
use File::Basename qw(dirname);

use Path::Class;
use Config;
use JSON;


__PACKAGE__->add_property('task_name' => 'Core');
__PACKAGE__->add_property('static_dir' => 'static');
__PACKAGE__->add_property('docs_markup' => 'pod');


#================================================================================================================================================================================================================================================
sub new {
    my $self = shift->SUPER::new(@_);
    
    $self->add_build_element('js');
    
    $self->add_build_element('static');
    
    $self->install_base($self->get_jsan_libroot) unless $self->install_base;
    $self->install_base_relpaths(lib  => 'lib');
    $self->install_base_relpaths(arch => 'arch');
    
    return $self;
}



#================================================================================================================================================================================================================================================
sub get_jsan_libroot {
	return $ENV{JSANLIB} || ($^O eq 'MSWin32') ? 'c:\JSAN' : (split /\s+/, $Config{'libspath'})[1] . '/jsan';
}


#================================================================================================================================================================================================================================================
sub process_static_files {
	my $self = shift;
	
	my $static_dir = $self->static_dir;
  
  	return if !-d $static_dir;
  
  	#find all files except directories
  	my $files = $self->rscan_dir($static_dir, sub {
  		!-d $_
  	});
  	
	foreach my $file (@$files) {
		$self->copy_if_modified(from => $file, to => File::Spec->catfile($self->blib, 'lib', $self->dist_name_as_dir, $file) );
	}
  	
}


#================================================================================================================================================================================================================================================
sub ACTION_install {
    my $self = shift;
    
    require ExtUtils::Install;
    
    $self->depends_on('build');
    
    my $map = $self->install_map;
    my $dist_name = quotemeta $self->dist_name();
    
    #trying to be cross-platform
    my $dist_name_to_dir = catdir( split(/\./, $self->dist_name()) );
    
    $map->{'write'} =~ s/$dist_name/$dist_name_to_dir/;
    
    ExtUtils::Install::install($map, !$self->quiet, 0, $self->{args}{uninst}||0);
}


#================================================================================================================================================================================================================================================
sub dist_name_as_dir {
	return split(/\./, shift->dist_name());
}


#================================================================================================================================================================================================================================================
sub comp_to_filename {
	my ($self, $comp) = @_;
	
    my @dirs = split /\./, $comp;
    $dirs[-1] .= '.js';
	
	return file('lib', @dirs);
}


#================================================================================================================================================================================================================================================
sub ACTION_task {
    my $self = shift;
    
	my $components = file('Components.JS')->slurp;

	#removing // style comments
	$components =~ s!//.*$!!gm;

	#extracting from most outer {} brackets
	$components =~ m/(\{.*\})/s;
	$components = $1;

	my $deploys = decode_json $components;
	
	#expanding +deploy_variant entries
	foreach my $deploy (keys(%$deploys)) {
		
		$deploys->{$deploy} = [ map { 
			
			/^\+(.+)/ ? @{$deploys->{$1}} : $_;
			
		} @{$deploys->{$deploy}} ];
	}

	$self->concatenate_for_task($deploys, $self->task_name);
}


#================================================================================================================================================================================================================================================
sub concatenate_for_task {
    my ($self, $deploys, $task_name) = @_;
    
    if ($task_name eq 'all') {
    	
    	foreach my $deploy (keys(%$deploys)) {
    		$self->concatenate_for_task($deploys, $deploy);  	
    	}
    
    } else {
	    my $components = $deploys->{$task_name};
	    die "Invalid task name: [$task_name]" unless $components;
	    
	    my @dist_dirs = split /\./, $self->dist_name();
	    push @dist_dirs, $task_name;
	    $dist_dirs[-1] .= '.js';
	    
	    my $bundle_file = file('lib', 'Task', @dist_dirs);
	    $bundle_file->dir()->mkpath();
	    
	    my $bundle_fh = $bundle_file->openw(); 
	    
	    foreach my $comp (@$components) {
	        print $bundle_fh $self->comp_to_filename($comp)->slurp . ";\n";
	    }
	    
	    $bundle_fh->close();
    };
}


#================================================================================================================================================================================================================================================
sub ACTION_test {
	my ($self) = @_;
	
	my $result = (system 'jsan-prove') >> 8;
	
	if ($result == 1) {
		print "All tests successfull\n";
	} else {
		print "There were failures\n";
	}
}


#================================================================================================================================================================================================================================================
sub ACTION_dist {
    my $self = shift;

    $self->depends_on('docs');
    $self->depends_on('manifest');
    $self->depends_on('distdir');

    my $dist_dir = $self->dist_dir;

    $self->_strip_pod($dist_dir);

    $self->make_tarball($dist_dir);
    $self->delete_filetree($dist_dir);

    $self->add_to_cleanup('META.json');
#    $self->add_to_cleanup('*.gz');
}



#================================================================================================================================================================================================================================================
sub ACTION_docs {
    my $self = shift;
    
    $self->depends_on('manifest');
    
    #preparing 'doc' directory possible adding to cleanup 
    my $doc_dir = catdir 'doc';
    
    unless (-e $doc_dir) {
        File::Path::mkpath($doc_dir, 0, 0755) or die "Couldn't mkdir $doc_dir: $!";
        
        $self->add_to_cleanup($doc_dir);
    }
    
    my $markup = $self->docs_markup;
    
    if ($markup eq 'pod') {
        $self->generate_docs_from_pod()
    } elsif ($markup eq 'md') {
        $self->generate_docs_from_md()
    } elsif ($markup eq 'mmd') {
        $self->generate_docs_from_mmd()
    }
}


#================================================================================================================================================================================================================================================
sub generate_docs_from_md {
    my $self = shift;
    
    require Text::Markdown;
    
    $self->extract_inlined_docs({
        html => \sub {
            my ($comments, $content) = @_;
            return (Text::Markdown::markdown($comments), 'html')
        },
        
        md => \sub {
            my ($comments, $content) = @_;
            return ($comments, 'txt');
        }
    })
}


#================================================================================================================================================================================================================================================
sub generate_docs_from_mmd {
    my $self = shift;
    
    require Text::MultiMarkdown;
    
    $self->extract_inlined_docs({
        html => sub {
            my ($comments, $content) = @_;
            return (Text::MultiMarkdown::markdown($comments), 'html')
        },
        
        mmd => sub {
            my ($comments, $content) = @_;
            return ($comments, 'txt');
        }
    })
}


#================================================================================================================================================================================================================================================
sub extract_inlined_docs {
    my ($self, $convertors) = @_;
    
    my $markup      = $self->docs_markup;
    my $lib_dir     = dir('lib');
    my $js_files    = $self->find_dist_packages;
    
    
    foreach my $file (map { $_->{file} } values %$js_files) {
        (my $separate_docs_file = $file) =~ s|\.js$|.$markup|;
        
        my $content = file($file)->slurp;
        
        my $docs_content = -e $separate_docs_file ? file($separate_docs_file)->slurp : $self->strip_doc_comments($content);


        foreach my $format (keys(%$convertors)) {
            
            #receiving formatted docs
            my $convertor = $convertors->{$format};
            
            my ($result, $result_ext) = &$convertor($docs_content, $content);
            
            
            #preparing 'doc' directory for current format 
            my $format_dir = catdir 'doc', $format;
            
            unless (-e $format_dir) {
                File::Path::mkpath($format_dir, 0, 0755) or die "Couldn't mkdir $format_dir: $!";
                
                $self->add_to_cleanup($format_dir);
            }
            
            
            #saving results
            (my $res = $file) =~ s|^$lib_dir|$format_dir|;
            
            $res =~ s/\.js$/.$result_ext/;
            
            my $res_dir = dirname $res;
            
            unless (-e $res_dir) {
                File::Path::mkpath($res_dir, 0, 0755) or die "Couldn't mkdir $res_dir: $!";
                
                $self->add_to_cleanup($res_dir);
            }
            
            open my $fh, ">", $res or die "Cannot open $res: $!\n";
    
            print $fh $result;
    
            close $fh;
        }
    }
}



#================================================================================================================================================================================================================================================
sub strip_doc_comments {
    my ($self, $content) = @_;
    
    my @comments = ($content =~ m[^\s*/\*\*(.*?)\*/]msg);
    
    return join '', @comments; 
}


#================================================================================================================================================================================================================================================
sub generate_docs_from_pod {
    my $self = shift;

    require Pod::Simple::HTML;
    require Pod::Simple::Text;
    require Pod::Select;

    for (qw(html text pod)) {
        my $dir = catdir 'doc', $_;
        
        unless (-e $dir) {
            File::Path::mkpath($dir, 0, 0755) or die "Couldn't mkdir $dir: $!";
            
            $self->add_to_cleanup($dir);
        }
    }

    my $lib_dir  = catdir 'lib';
    my $pod_dir  = catdir 'doc', 'pod';
    my $html_dir = catdir 'doc', 'html';
    my $txt_dir  = catdir 'doc', 'text';

    my $js_files = $self->find_dist_packages;
    
    foreach my $file (map { $_->{file} } values %$js_files) {
        (my $pod = $file) =~ s|^$lib_dir|$pod_dir|;
        
        $pod =~ s/\.js$/.pod/;
        
        my $dir = dirname $pod;
        
        unless (-e $dir) {
            File::Path::mkpath($dir, 0, 0755) or die "Couldn't mkdir $dir: $!";
        }
        
        # Ignore existing documentation files.
        next if -e $pod;
        
        
        open my $fh, ">", $pod or die "Cannot open $pod: $!\n";

        Pod::Select::podselect( { -output => $fh }, $file );

        print $fh "\n=cut\n";

        close $fh;
    }
    

    for my $pod (@{Module::Build->rscan_dir($pod_dir, qr/\.pod$/)}) {
        # Generate HTML docs.
        (my $html = $pod) =~ s|^\Q$pod_dir|$html_dir|;
        
        $html =~ s/\.pod$/.html/;
        
        my $dir = dirname $html;
        
        unless (-e $dir) {
            File::Path::mkpath($dir, 0, 0755) or die "Couldn't mkdir $dir: $!";
        }
        
        open my $fh, ">", $html or die "Cannot open $html: $!\n";
        
        my $parser = Pod::Simple::HTML->new;
        $parser->output_fh($fh);
        $parser->parse_file($pod);
        
        close $fh;

        # Generate text docs.
        (my $txt = $pod) =~ s|^\Q$pod_dir|$txt_dir|;
        
        $txt =~ s/\.pod$/.txt/;
        
        $dir = dirname $txt;
        
        unless (-e $dir) {
            File::Path::mkpath($dir, 0, 0755) or die "Couldn't mkdir $dir: $!";
        }
        
        open $fh, ">", $txt or die "Cannot open $txt: $!\n";
        
        $parser = Pod::Simple::Text->new;
        $parser->output_fh($fh);
        $parser->parse_file($pod);
        
        close $fh;
    }
}


#================================================================================================================================================================================================================================================
sub _write_default_maniskip {
    my $self = shift;
    my $file = shift || 'MANIFEST.SKIP';

    $self->SUPER::_write_default_maniskip($file);

    my $fh = IO::File->new(">> $file") or die "Can't open $file: $!";
    print $fh <<'EOF';
^\.project$
^\.git\b
^\.externalToolBuilders\b
EOF
    $fh->close();
}



#================================================================================================================================================================================================================================================
# Overriding newly created Module::Build method, which add itself to 'configure_requires' - we need to keep it clean
sub auto_require {
    
}


#================================================================================================================================================================================================================================================
# Overriding Module::Build method, which checks for prerequisites being installed 
sub check_prereq {
    return 1
}


#================================================================================================================================================================================================================================================
# Overriding Module::Build method, which checks some other feature 
sub check_autofeatures {
    return 1
}


#================================================================================================================================================================================================================================================
sub prepare_metadata {
    my ($self, $node, $keys, $args) = @_;
    
    $self->meta_add('static_dir' => $self->static_dir);
    
    return $self->SUPER::prepare_metadata($node, $keys, $args);    
}



__PACKAGE__ # nothingmuch (c) 

__END__

#line 568


#line 742


