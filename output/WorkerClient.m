classdef WorkerClient

properties
    workerInfo
    messenger
    status
end % properties

methods
    function this = WorkerClient()
        this.workerInfo = OI.WorkerInformation(this);
    end % constructor

    function [result, error] = run(this, task)
        [result, error] = this.workerInfo.run(task);
    end % run

    function id = id( this )
        % Shortcut to get the id from the worker info struct
        id = this.workerInfo.id;
    end % function

    function this = update_status(this, task)
        % Update the status of the worker
        this.status = task;
        % Tell the server our status
        this.messenger.send( ...
            OI.Message.update_worker(this.id, 'status', this.status) ...
            );
    end % function

    function this = main(this)

        % Connect to the server
        assert(~isempty(this.messenger), 'No messenger specified');
        this.messenger = this.messenger.connect();

        % Register the worker
        this.messenger.send( ...
            OI.Message.register_worker(this.id) ...
            );

        % Main loop
        while true
            % Get a task
            task = this.messenger.send( ...
                OI.Message.get_job(this.id) ...
                );

            % Check the task
            if isempty(task)
                fprintf(1, 'No task received')
                % Ask for a new task
                response = this.messenger.send( ...
                    OI.Message.ready_for_job(this.id) ...
                    );
                assert(response, 'No response from server')
                break;
            end % if

            fprintf(1, 'Received task: %s\n', task)

            % load and validate the task
            job = OI.Job(task);

            % Add the job to the queue
            engine.queue.add_job(job);

            while ~oi.engine.queue.is_empty()
                dbSize = numel(engine.database.data);
                try
                    oi.engine.run_next_job();
                catch err
                    fprintf(1, 'Error running job: %s\n', err.message);
                    this.update_status('error', err.message);
                end % try
            end % while ~oi.engine.queue.is_empty()

            % Check the plugin 
            if engine.plugin.isFinished
                answer = '';
                if dbSize < numel(oi.engine.database.data)
                    lastEntry = oi.engine.database.data{end};
                    if (isa(lastEntry,'OI.Data.DataObj') && ~lastEntry.hasFile) ...
                            || isstruct(lastEntry)
                        % convert the database additions to xml
                        resultAsStruct = OI.Functions.obj2struct( lastEntry );
                        resultAsXmlString = OI.Functions.struct2xml( resultAsStruct ).to_string();
                        answer = resultAsXmlString;
                    end
                end
            end % if engine.plugin.isFinished

            % Tell the server we are done
            this.messenger.send( ...
                OI.Message.job_done(this.id, task, answer) ...
                );

        end % while main loop

        % Run the task
    end % main
end % methods

end % classdef
