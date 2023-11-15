pwd
% check if the OI package is in the path
if isempty(strfind(path, 'OI'))
    cd output
end


%% Load the example project using the old file structure

% instantiate the project object
projObj = OI.Data.ProjectDefinition();
assert(isa(projObj, 'OI.Data.ProjectDefinition'), 'Project object is not of the correct class');
assert(isempty(projObj.PROJECT_NAME), 'Project name should be empty');

% load the dummy project
example_project_filepath = fullfile(pwd, '+OI', 'Examples', 'ExampleProject_template.oi');
content = fileread(example_project_filepath);
props = properties(OI.Data.ProjectDefinition);
projOptStruct = OI.Data.ProjectDefinition.load_from_legacy_file(content);
projObj = projObj.format_properties(projOptStruct);

% test
assert(strcmpi(projObj.PROJECT_NAME, 'OpenInSAR_Project'), 'Project name should have been loaded');


%% Load the example project using XML

% instantiate the project object
projObj = OI.Data.ProjectDefinition();
assert(isa(projObj, 'OI.Data.ProjectDefinition'), 'Project object is not of the correct class');
assert(isempty(projObj.PROJECT_NAME), 'Project name should be empty');

% load the dummy project
example_project_filepath = fullfile(pwd, '+OI', 'Examples', 'ExampleProject_template.xml');
content = fileread(example_project_filepath);
props = properties(OI.Data.ProjectDefinition);
projOptStruct = OI.Data.ProjectDefinition.load_from_xml(content);
projObj = projObj.format_properties(projOptStruct);

% test
assert(strcmpi(projObj.PROJECT_NAME, 'OpenInSAR_Project_X'), 'Project name should have been loaded');
