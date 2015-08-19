package PODWebView;

use Dancer ':syntax';
use Dancer::Plugin::Preprocess::Markdown;
use Cwd qw(abs_path);
use Pod::Simple::HTML;
use File::Slurp;
use File::Find;

use Data::Dumper;

our $VERSION = '0.1';

my $p = Pod::Simple::HTML->new;

get '/' => sub {
    template 'index', {file_size_limit => config->{app_settings}->{file_size_limit}};
};

get '/project' => sub {

    template 'project', {file_size_limit => config->{app_settings}->{file_size_limit}};
};

sub get_file_content
{
    my $urls   = shift;
    my $string = read_file($urls);
    return $string;
}

post '/podhtml' => sub {
    if (request->is_ajax) {

        my $pod     = params->{pod};
        my $is_path = params->{is_path};

        if (defined $is_path) {
            $pod = get_file_content($pod);
        }

        eval { return process_pod($pod); } or do {

            # We can recover from some errors by creating a new instance of the
            # parser object, so let's try that.
            $p = Pod::Simple::HTML->new;
            return process_pod($pod);
        };
    }
    else {
        return error("Not allowed", 403);
    }
};

sub get_pmfiles_path
{

    my $dir = shift;
    return unless defined $dir && -d $dir;
    $dir =~ s#\\#/#g;    # Win32 :-(
    my @paths;

    find sub {
        return if (-di && $_ eq '');
        if (-f && /.pm$/) {
            push(@paths, $File::Find::name);
        }
    }, $dir;

    return \@paths;

}
post '/getconfigprojectnames' => sub {

    if (request->is_ajax) {
        my @projects = split ',', config->{project_settings}->{load_projects};

        my @project_names;
        foreach my $path (@projects) {
            my @dirs = split '/', $path;
            my $name = pop @dirs;

            push(@project_names, [$path, $name]);
        }
        return to_json({project_names => \@project_names});
    }
};

post '/load_tree' => sub {

    if (request->is_ajax) {
        my $path  = params->{path};
        my $paths = get_pmfiles_path($path);
        my $tree  = get_tree_structure($paths, $path);
        return to_json({tree => $tree});
    }
};

sub process_pod
{
    my ($pod) = @_;

    $p->output_string(\my $html);
    $p->parse_string_document($pod);
    $p->reinit;

    return $html || "<center>POD not found in this module</center>";
}

sub get_tree_structure
{

    my ($url_ref, $config_path) = @_;

    my @urls = reverse @{$url_ref};
    my @tree;
    my %id_hash;
    my $id     = -1;
    my $url_id = -1;

    #regex for find the parent directories of project
    my $prefix_remover;
    if ($config_path) {
        $config_path =~ /(.+\/)+(.+\/)/;
        my $prefix_str = $1;

        #regex for remove parent directories of project
        $prefix_remover = qr/$prefix_str(\/?.+)+/;
    }

    foreach my $path (@urls) {

        $url_id++;
        my $parent_id = -1;

        #remove the prefix
        my $extracted_path;
        if ($config_path && $path =~ $prefix_remover) {
            $extracted_path = "/$1";
        }
        else {
            $extracted_path = $path;
        }

        my @folders = split '/', $extracted_path;
        my $need_slash;
        my $file = pop @folders;

        if ($folders[0]) {
            $need_slash = 0;
        }
        else {

            shift @folders;
            $need_slash = 1;
        }

        my $path_str = $need_slash ? '/' : '';

        foreach my $folder (@folders) {
            $path_str .= "$folder/";

            if (!defined $id_hash{$path_str}) {
                $id++;
                $id_hash{$path_str} = $id;
                push(@tree, [$id, $parent_id, "'$folder'", $path]);
                $parent_id = $id;
            }
            else {
                $parent_id = $id_hash{$path_str};
            }
        }

        $parent_id = $id_hash{$path_str};
        $id++;
        push(@tree, [$id, $parent_id, "'$file'", "#/$url_id", $path]);
    }
    return \@tree;
}

post '/gettree' => sub {

    if (request->is_ajax) {

        my @urls1 = split '~', params->{url};

        my $tree = get_tree_structure(\@urls1);

        my $tree_struct = to_json({tree => $tree});

        return $tree_struct;
    }

};

true;
