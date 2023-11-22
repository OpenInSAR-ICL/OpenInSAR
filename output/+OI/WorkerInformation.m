classdef WorkerInformation

properties
    id
    startDirectory
    nCpus
end

methods
    function obj = WorkerInformation( obj )
        % Get the worker ID from the environment
        obj = obj.get_worker_index();
        % Get the number of available cores
        obj = obj.get_max_cpus();
        [~,obj.startDirectory] = fileparts(pwd);
    end

    function obj = get_worker_index( obj )
        % Get the worker ID from the environment
        obj.id = getenv('PBS_ARRAY_INDEX');
        % Convert to a number
        if ~isempty(obj.id) && ~isnumeric(obj.id)
            obj.id = str2double(obj.id);
        end
        % if it doesn't exist, use a random integer
        if isempty(obj.id)
            obj.id = randi(100) + 1000;
            warning('PBS_ARRAY_INDEX environment variable not set. Using random integer.');
        end
    end

    function obj = get_max_cpus( obj )
        % get number of available cores
        nCpu = getenv('ICL_LAUNCHER_ARG_NUM_CORES'); % default to 1
        % nCpu = getenv('nCpu') % old name
        if isempty(nCpu)
            nCpu = '1';
        end
        nCpu = str2double(nCpu);
        obj.nCpus = nCpu;
        maxNumCompThreads(nCpu);
    end

end % methods

end % classdef