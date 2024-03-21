% Main entry point
% This will load projects, run plugins, and get data objects
% Handle command line arguments
% -project: path to a project file which will be loaded.
% -run: name of a plugin to run.
% -get: name of a data object to get.
% -job: string defining a specific job to run.
% -help: display help

% Properties are an instance of the engine class
% an instance of a ui for logging
% and a configuration structure
classdef OpenInSAR

properties
    engine = OI.Engine();
    ui = OI.UserInterface();
    configuration = struct( ...
        'isActive',true, ...
        'isRunningAutomatically',false, ...
        'isDebug',false ...
        );
end

methods
    function this = OpenInSAR(varargin)
        if nargin ~= 0
            % Handle command line arguments
            this = this.parse_args(varargin{:});
        end
        
        % Run any neccessary first-time setup
        this.setup();

        if this.configuration.isActive
            % Run main
            this = this.main();
        end
        this.configure();
        
    end

    function this = parse_args( this, varargin )

        for i = 1:2:nargin-1
            switch varargin{i}
                case '-auto'
                    % Run in auto mode
                    this.configuration.isRunningAutomatically = true;
                case '-manual'
                    % Run in manual mode
                    this.configuration.isRunningAutomatically = false;
                case '-get'
                    % Get data object
                    this.engine.load_object(varargin{i+1});
                case '-job'
                    % Run a specific job
                    this.engine.run_job(varargin{i+1});
                case '-log'
                    % Set log level of ui
                    this.ui.set_debug_level(varargin{i+1})

                case '-project'
                    % Load project
                    this.engine.load_project(varargin{i+1});
                case '-run'
                    % Run plugin
                    plugin = PluginFactory(varargin{i+1});
                    this.engine.plugin = plugin;

                otherwise
                    % Unknown argument
                    this.ui.log('error', 'Unknown argument: %s', varargin{i})
            end
        end
    end

    function this = load_object( this, varargin )
        % Load a data object
        % This will check the database for any existing files
        % and add any jobs to the queue where needed
        % This will then return the data object, which can be used to get the filename
        % and run the plugin
        this.ui.log('info', 'Loading a data object \n')
        this.engine.load(varargin{:});
    end

    function this = run_next_job( this )
        % Run the next job in the queue
        this.engine.run_next_job();
    end

    function this = configure(this)
        this.engine.ui = this.ui;
    end

    function this = main(this, varargin)
        currentProject = this.engine.load( OI.Data.ProjectDefinition() );
        this.ui.log('info','Project: %s is now active\n', ...
            currentProject.PROJECT_NAME);
        this.ui.log('debug', 'Starting OpenInSAR main\n');
    end

    function this = setup(this, varargin)
        % Run any neccessary first-time setup
        this.ui.log('debug', 'Running setup\n');
        [~,currentDir] = fileparts(pwd);
        % Check if we are in the correct directory
        if ~strcmp(currentDir, 'OpenInSAR')
            this.ui.log('info', 'Starting directory is %s\n', strrep(pwd,'\','\\'));
        end
        % Check if there is an xml file linking us to the current project
        if exist('CurrentProject.xml', 'file')
            curProj = this.engine.database.fetch('project');
            if isempty(curProj)
                this.engine.ui.log('debug', 'Found CurrentProject.xml\n');
                this.load_current_project();
            end
        else
            this.engine.ui.log('info', 'Running first time setup. (No CurrentProject.xml found)\n');
            % Create a new project
            this.create_project();
        end
    end

    function this = load_current_project(this, varargin)
        % Get the listed project path
        currentProjectPath = OI.ProjectLink().projectPath;
        this.ui.log('info', 'Loading current project at %s\n', ...
            strrep(currentProjectPath,'\','\\'))
        if exist(currentProjectPath, 'file')
            % Load the project
            this.engine.load_project(currentProjectPath);

        else
            % Throw an error and try to create a new project
            this.ui.log('error', 'Could not find project at %s\n', ...
                strrep(currentProjectPath,'\','\\'));
            error(['Could not find project at %s\n', ...
                'Please check CurrentProject.xml\n'], currentProjectPath);
        end
    end

    function this = create_project(this, varargin)
        % Create a new project
        this.ui.log('info', 'Creating a new project\n');
        % For now we will just copy the template examples
        newProjectPath = fullfile(fileparts(pwd), 'ExampleProject.oi');
        curr_proj_template = ...
            fullfile('+OI','Examples','CurrentProject_template.xml');
        example_proj_template = ...
            fullfile('+OI','Examples','ExampleProject_template.oi');
        copyfile(curr_proj_template, 'CurrentProject.xml');
        % Don't overwrite an existing project
        if exist(newProjectPath, 'file')
            warning( ...
            'A project already exists at %s\nThis was not overwritten.', ...
            newProjectPath)
        else
            this.engine.ui.log('info', ...
                'Creating a new project at %s\n', ...
                strrep(newProjectPath,'\','/')) % Octave doesn't like '\'
            copyfile(example_proj_template, newProjectPath);
        end

        % Throw an error to stop execution
        warning( [ ...
        'A new project has been created at \n\t%s\n\n' ...
        'You will now need to manually edit this file to define your project\n', ...
        'If you wish to move this project file, please also edit CurrentProject.xml\n', ...
        'CurrentProject.xml should contain the path to the current project file\n', ...
        ], ...
        newProjectPath);
        error('Please read instructions above before continuing')

    end
end

end
