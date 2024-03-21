% This is a software for processing MTI deformation data.
% The main 'OpenInSAR' entry point takes command line arguments.
% -project: path to a project file which will be loaded.
% -run: name of a plugin to run.

% Loading a project will initialise a database.
% The database will check for existing files (when requested)
% By instantiating the data object requested, and determining its unique filename
% (which is a method of the data object) which is with respect to the paticulars of the project (such as where the project work directory is)
% A plugin will check it has all available inputs, and then run.
% A plugin runner (in the main entrypoint) will by default check for the existence of the output files, and if they all exist, not run the plugin.

% OpenInSAR:
%   load project into db
%   configure
%   run plugin

% Database
%   check for existing files

% DataObj
%   get filename
%   report missing files and variables
%   create a job to produce a given dataObj

% Plugin
%    validate:
%       check for missing files and variables, add jobs to queue where needed
%    run:
%       run the plugin, produce the output dataObjs

% Engine
%    run jobs in queue
%    run plugins in queue

% % Load a project and request results
% OpenInSAR('project', 'project.xml', 'get', 'PSI_Velocity');
% % This calls a DataFactory to create a PSI_Velocity object
% % This creates a PSI_Velocity object

% % OpenInSAR then calls Engine.load( PSI_Velocity )
% % which calls Database.get(PSI_Velocity)
% % which makes use of the PSI_Velocity.getFilename( engine / project ) method
% % Any variables needed to get the filename are accessed via Engine.load( variable )
% % Database checks for the existence of the file, and if it exists, returns the filename
% % If it doesn't exist, it creates a job to produce it, and adds it to the engine.queue
% % via Engine.addJob(PSI_Velocity)
% % which calls PSI_Velocity.createJob( engine );
% % which can be adapted to take into account paticular settings in the database, such as if theres any different methods requested
% % The engine proceeds to run the next job in the queue.
% % Which is something like CreatePsiVelocityMaps
% % This calls Engine.load( PsiInversionResults ) or something

% % after each call to load we need to handle the output, and return if further work is needed beforehand

% % Eventually we will find something we have data for.
% % Database.get( ProjectDefinition ) will return the project structure

% % Database is just a structure mapping the unique name of an object to its DataObj and filename
% Calling Load will do different things depending on something in the DataObj?

classdef ProjectDefinition < OI.Data.DataObj

properties
    id = 'ProjectDefinition';

    PROJECT_NAME

    AOI
    START_DATE = OI.Data.Datetime('20000101','yyyymmdd')
    END_DATE = OI.Data.Datetime('20301231','yyyymmdd')

    TRACKS
    INPUT_DATA_LIST
    POLARIZATION = 'VV,VH,HH';
    PROCESSING_SCHEME

    BLOCK_SIZE = 5000; %m
    MASK_SEA = 1;

    HERE
    HOME
    ROOT
    WORK
    INPUT_DATA_DIR
    OUTPUT_DATA_DIR
    ORBITS_DIR = '$WORK$/Orbits/'
    pathVars = {'HERE','HOME','ROOT','WORK','INPUT_DATA_DIR','OUTPUT_DATA_DIR','ORBITS_DIR'}

    SECRETS_FILEPATH = '$HOME$/.OpenInSAR/secrets.txt'
end

methods

    function this = ProjectDefinition( filename )
        if nargin > 0
            this = OI.Data.ProjectDefinition.load_from_file( filename );
            % set up project directories
            this = this.setup_project_directories();
        end
    end

    function this = get_relative_paths(this)

        % get 'ROOT', the root directory of the OpenInSAR script
        this.ROOT = fileparts(fileparts(fileparts( mfilename( 'fullpath' ) )));

        % get 'HERE', the directory of the project definition file
        hereFolder = fileparts( this.filepath );
        if isempty(hereFolder)
            hereFolder = pwd;
        end
        this.HERE = fullfile( hereFolder );

        % get 'HOME', the users home directrory
        this.HOME = OI.OperatingSystem.get_usr_dir();
    end

    function this = format_properties( this, optionsStruct )

        % split the optionsStruct into key/value pairs
        keys = fieldnames( optionsStruct );
        for ii = 1:length(keys)
            key = keys{ii};
            value = optionsStruct.(key);
            switch key
            case 'OUTPUT_DATA_DIR'
                this.OUTPUT_DATA_DIR = value;
                this.WORK = value;
            case 'PROJECT_NAME'
                this.PROJECT_NAME = value;
            case 'AOI'
                this.AOI = OI.Data.AreaOfInterest( value );
            case {'START_DATE', 'END_DATE'}
                switch numel(value) % handle different date formats here
                    case 8
                        this.(key) = OI.Data.Datetime(value,'yyyymmdd');
                    otherwise
                        this.(key) = OI.Data.Datetime(value); % see what we get
                end
            otherwise
                this.(key) = value;
            end % switch
        end % for
    end

    function this = setup_project_directories( this )
        % set up project directories
        OI.Functions.mkdirs( this.WORK );
        OI.Functions.mkdirs( this.OUTPUT_DATA_DIR );
        OI.Functions.mkdirs( this.INPUT_DATA_DIR );
        OI.Functions.mkdirs( this.ORBITS_DIR );
    end

end% methods

methods (Static)

    function this = load_from_file( filename )
        this = OI.Data.ProjectDefinition();
        this.filepath = filename;

        % get special paths like ROOT, HERE, HOME
        this = this.get_relative_paths();

        % read in file
        fId = fopen( filename, 'r' );
        fileContent = fread( fId, Inf,  '*char' )';
        fclose( fId );

        % now switch based on file being XML or old format
        if OI.Compatibility.contains(filename,'.xml') || ~isempty( regexp( fileContent, '<\?xml', 'once' ) )
            optionsFromFile = this.load_from_xml( fileContent );
        elseif OI.Compatibility.contains(filename,'.oi')
            optionsFromFile = this.load_from_legacy_file( fileContent );
        else
            warning('Could not determine file type of %s', filename);
            try
                optionsFromFile = this.load_from_xml( fileContent );
            catch
                try
                    optionsFromFile = this.load_from_legacy_file( fileContent );
                catch   
                    error('Could not parse file %s', filename);
                end
            end
        end
        
        this = this.format_properties(optionsFromFile);
        propertyKeys = properties( this );

        % string interpolation of the properties
        for i = 1:length(propertyKeys)
            if OI.Compatibility.is_string( this.(propertyKeys{i}) )
                this.(propertyKeys{i}) = this.string_interpolation( this.(propertyKeys{i}) );
            end
        end

    end%load constructor
    


    function optionsStruct = load_from_xml( fileContent )
        assert( nargin > 0, 'must provide a char/string of xml, and a cell of properties to load' );
        assert( ischar( fileContent ), 'content must be a char/string' );
        x = OI.Data.XmlFile( fileContent );
        optionsStruct = x.to_struct();
    end % load from xml


    function optionsStruct = load_from_legacy_file( fileContent )

        optionsStruct = struct();

        % split into lines
        lines = strsplit( fileContent,'\n' );

        % remove anything after a # (comments)
        lines = cellfun( @(x) strsplit( x, '#' ), lines, 'UniformOutput', false );
        lines = cellfun( @(x) x{1}, lines, 'UniformOutput', false );

        % remove empty lines
        lines = lines( ~cellfun( @isempty, lines ) );

        % split into key/value pairs
        kv = cellfun( @(x) strsplit( x, '=' ), lines, 'UniformOutput', false );

        % remove spaces
        kv = cellfun( @(x) cellfun( @(y) strtrim(y), x, 'UniformOutput', false ), kv, 'UniformOutput', false );

        % remove empty cells
        kv = cellfun( @(x) x( ~cellfun( @isempty, x ) ), kv, 'UniformOutput', false );

        % Set the properties
        for i = 1:length(kv)
            % remove empty line at end
            if isempty(kv{i})
               continue
            end
            key = kv{i}{1};
            value = kv{i}{2};
            if numel(value) && value(end) == ';'
                value = value(1:end-1);
            end
            optionsStruct.(key) = value;
        end%read in properties
    end % function

end% methods (Static

end
