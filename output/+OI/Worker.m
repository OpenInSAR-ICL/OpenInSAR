classdef Worker
   
    properties
        client = [];
        engine = [];
        data_directory = '';
    end

    methods

        function self = Worker(host, username, password, data_directory)
            if nargin == 4
                self.client = OI.BaseClient(host);
                self.client = self.client.login(username, password);
                self.client = self.client.register();
                self.data_directory = data_directory;
            else 
                api_host = getenv('OI_API_HOST');
                username = getenv('OI_USERNAME');
                password = getenv('OI_PASSWORD');
                self.data_directory = getenv('data_directory')
                if isempty(api_host) || isempty(username) || isempty(password)
                    error('Worker:Worker', ...
                    ['API host, username, and password must be set', ...
                    ' by either arguments or environment variables']);
                end
                self.client = OI.BaseClient(api_host);
                self.client = self.client.login(username, password);
                self.client = self.client.register();
            end
            self.engine = OI.Engine();
        end % Worker
        

        function [self, job] = get_job(self)
            job = self.client.find_job;
            while isempty(job)
                disp('Waiting for job from server');
                pause(10)
                job = self.client.find_job;
            end
        end % run

        function [self, job] = get_assignment(self)
            
            % check if the job is assigned to this worker
            while true
                [self, job] = self.get_job();
                assignments = self.client.list_assignments();
                matchAssignment = ...
                    arrayfun(@(x) x.worker == self.client.worker_id && x.job == job.id, assignments);
                if any(matchAssignment)
                    self.client.assignmentId = assignments(matchAssignment).id;
                    disp('Waiting for server to ack assignment');
                    pause(10)
                else
                    % post the assignment to acknowledge the job
                    self.client = self.client.post_assignment(job);
                    break
                end
            end

        end % get_assignment

        function run(self)
            while true
                [self, job] = self.get_assignment();
                projectData = self.client.get_project_by_id(job.project);
                projectData.DATA_DIRECTORY = self.data_directory;
                self.engine.load_project(projectData);
                self.client = self.client.job_started(job);
                disp(['Running job: ' job.name]);
                self.engine.queue.add_job(self.client.json2job(job),1);
                dbSize = numel(self.engine.database.data);
                self.engine.run_next_job();
                if self.engine.plugin.isFinished()
                    result = '';
                    if dbSize < numel(self.engine.database.data)
                        result = self.format_result();
                    end
                    self.client.job_done(result);
                else
                    self.client.job_failed([self.engine.ui.m_output.messageHistory{:}]);
                end
            end
        end % run

        function base64answer = format_result(self)
            lastEntry = self.engine.database.data{end};
            base64answer = '';
            if (isa(lastEntry,'OI.Data.DataObj') && ~lastEntry.hasFile) ...
                    || isstruct(lastEntry)
                % convert the database additions to xml
                resultAsStruct = OI.Functions.obj2struct( lastEntry );
                resultAsXmlString = OI.Functions.struct2xml( resultAsStruct ).to_string();
                answer = resultAsXmlString;
                base64answer = OI.Compatibility.base64encode(answer);
            end
        end % format_result
    end % methods
end

