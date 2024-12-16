classdef BaseClient
    properties
        root_url = '';
        csrfToken = '';
        sessionId = '';
        worker_id = '';
        username = '';
        userId = '';
        jobId = '';
        assignmentId = '';
        isWindows = false;
    end
    methods
        
        function self = BaseClient(root_url)
            self.root_url = root_url;
            self.isWindows = OI.OperatingSystem.isWindows();
        end

        function self = register(self, machine_id)
            if isempty(self.username)
                error('Not logged in');
            end
            
            if nargin < 2 || isempty(machine_id)
                [sc, hostname] =system('hostname');
                if sc
                    error('Could not get hostname');
                end
                if isempty(hostname)
                    error('Could not get hostname');
                end
                machine_id = [self.username '_' strip(hostname)];
                J = getenv('PBS_ARRAY_INDEX');
                if isempty(J)
                    randInds = randi(26,1,5);
                    chars=['A':'Z'];
                    J=chars(randInds);
                    J=J(:)';
                end
                machine_id = [machine_id '_' J];
            end
            vers = 'Octave1.0';
            workerUrl = [self.root_url 'workers/'];
            curlString = [
                'env -u LD_LIBRARY_PATH curl -k -sS -X POST ' workerUrl, ...
                ' -H "Cookie: csrftoken=' self.csrfToken, ';', ...
                ' sessionid=' self.sessionId '"', ...
                ' -H "X-CSRFToken: ' self.csrfToken '"', ...
                ' -H "Referer: ' workerUrl, '"'...
                ' -H "Content-Type: application/json"', ...
                sprintf(' -d "{\\\"machine_id\\\":\\\"%s\\\", \\\"processing_software_version\\\":\\\"%s\\\", \\\"user\\\":\\\"%s\\\"}"', machine_id, vers, num2str(self.userId)) ...
            ];

            % disp(curlString);
            if self.isWindows;curlString=strrep(curlString,'env -u LD_LIBRARY_PATH ','');end
            [status, response] = system(curlString);
            if status
                error(response)
            end
            % check for 'already exists' error
            if contains(response, 'already exists')
                disp('Worker already exists');
                workers = self.list_workers();
                matchWorker = ...
                    arrayfun(@(x) strcmpi(x.machine_id,machine_id), workers);
                if any(matchWorker)
                    self.worker_id = workers(matchWorker).id;
                else
                    error('Worker not found');
                end
            else
                self.worker_id = jsondecode(response).id;
            end
        end

        function [status, response] = curl_request(self, url, options)
            if ~isempty(options)
                options = [options ' '];
            end
            curlString = ['env -u LD_LIBRARY_PATH curl ' options self.root_url url];
            if self.isWindows;curlString=strrep(curlString,'env -u LD_LIBRARY_PATH ','');end
            [status, response] = system(curlString);
        end

        function self = get_csrf_for_login(self)
            [status, response] = self.curl_request('csrf/', '-L -k -sS -c -');
            if status
                error(response)
            end
            lines = strsplit(response,'#');
            self.csrfToken = jsondecode(lines{1}).csrfToken;
            fields = strsplit(lines{end},'\t');
            self.sessionId = strip(fields{end});
        end

        function self = get_logged_in_csrf(self, sessionId)
            [status, response] = self.curl_request('csrf/', ['-k -sS -c - -H "Cookie: sessionid=' sessionId '"']);
            if status
                error(status)
            end
            lines = strsplit(response,'#');
            self.csrfToken = jsondecode(lines{1}).csrfToken;
        end

        function [self, status, result] = login(self, username, password)
            self = get_csrf_for_login(self);
            % Construct curl command
            curlCommand = sprintf(['env -u LD_LIBRARY_PATH curl -k -L -sS -X POST %s -H "Content-Type: application/json" ', ...
                '-H "Cookie: sessionid=%s" ', ...
                '-H "X-CSRFToken: %s" ', ...
                '-H "Referer: %s" ', ...  % Add the Referer header
                '-c - ', ...
                '-d "{\\\"username\\\":\\\"%s\\\", \\\"password\\\":\\\"%s\\\"}"'], ...
                [self.root_url 'login/'], self.sessionId, self.csrfToken, [self.root_url 'login/'], username, password);

            % Execute the command
            if self.isWindows;curlCommand=strrep(curlCommand,'env -u LD_LIBRARY_PATH ','');end
            [status, result] = system(curlCommand);

            % Display the response
            % disp(result);

            % get the username from the json response
            lines=strsplit(result,'#');
            jsonRaw = lines{1};
             json = jsondecode(jsonRaw);
            self.username = json.username;
            self.userId = json.id;


            % get the session id
            fields=strsplit(lines{end},'\t');
            self.sessionId = strip(fields{end});
            
            % disp(result);
            self = self.get_logged_in_csrf(self.sessionId);

        end

        function projects = list_projects(self)
            % Construct curl command
            curlCommand = sprintf(['env -u LD_LIBRARY_PATH curl -k -sS -X GET %s ', ...
                '-H "Cookie: csrftoken=%s; sessionid=%s" ', ...
                ], ...
                [self.root_url 'projects/'], self.csrfToken, self.sessionId);

            % Execute the command
            if self.isWindows;curlCommand=strrep(curlCommand,'env -u LD_LIBRARY_PATH ','');end
            [status, projectsResponse] = system(curlCommand);

            % Display the response
            projects = jsondecode(projectsResponse);
        end

        function jobs = list_jobs(self)
            % Construct curl command
            curlCommand = sprintf(['env -u LD_LIBRARY_PATH curl -k -sS -X GET %s ', ...
                '-H "Cookie: csrftoken=%s; sessionid=%s" ', ...
                ], ...
                [self.root_url 'jobs/'], self.csrfToken, self.sessionId);

            % Execute the command
            if self.isWindows;curlCommand=strrep(curlCommand,'env -u LD_LIBRARY_PATH ','');end
            [status, jobsResponse] = system(curlCommand);

            % Display the response
            jobs = jsondecode(jobsResponse);
        end

        function aoiList = list_aois(self)
            curlCommand = sprintf(['env -u LD_LIBRARY_PATH curl -k -sS -X GET %s ', ...
                '-H "Cookie: csrftoken=%s; sessionid=%s" ', ...
                ], ...
                [self.root_url 'sites/'], self.csrfToken, self.sessionId);
            if self.isWindows;curlCommand=strrep(curlCommand,'env -u LD_LIBRARY_PATH ','');end
            [status, response] = system(curlCommand);
            aoiList = jsondecode(response);
        end

        function assignments = list_assignments(self)
            % Construct curl command
            curlCommand = sprintf(['env -u LD_LIBRARY_PATH curl -k -sS -X GET %s ', ...
                '-H "Cookie: csrftoken=%s; sessionid=%s" ', ...
                ], ...
                [self.root_url 'assignments/'], self.csrfToken, self.sessionId);

            % Execute the command
            if self.isWindows;curlCommand=strrep(curlCommand,'env -u LD_LIBRARY_PATH ','');end
            [status, assignmentsResponse] = system(curlCommand);

            % Display the response
            assignments = jsondecode(assignmentsResponse);
        end

        function projectTemplates = list_templates(self)
            % Construct curl command
            curlCommand = sprintf(['env -u LD_LIBRARY_PATH curl -k -sS -X GET %s ', ...
                '-H "Cookie: csrftoken=%s; sessionid=%s" ', ...
                ], ...
                [self.root_url 'projecttemplates/'], self.csrfToken, self.sessionId);

            % Execute the command
            if self.isWindows;curlCommand=strrep(curlCommand,'env -u LD_LIBRARY_PATH ','');end
            [status, response] = system(curlCommand);

            % Display the response
            % disp(response);
            projectTemplates = jsondecode(response);
        end

        function workers = list_workers(self)
            % Construct curl command
            curlCommand = sprintf(['env -u LD_LIBRARY_PATH curl -k -sS -X GET %s ', ...
                '-H "Cookie: csrftoken=%s; sessionid=%s" ', ...
                ], ...
                [self.root_url 'workers/'], self.csrfToken, self.sessionId);

            % Execute the command
            if self.isWindows;curlCommand=strrep(curlCommand,'env -u LD_LIBRARY_PATH ','');end
            [status, response] = system(curlCommand);

            % Display the response
            workers = jsondecode(response);
        end

        function myJob = find_job(self)
            assert(~isempty(self.worker_id), 'Worker not registered');
            jobs = self.list_jobs();
            matchJob = ...
                arrayfun(@(x) x.worker == self.worker_id, jobs);
            if any(matchJob)
                matchJob = find(matchJob,1);
                myJob = jobs(matchJob);
            else
                myJob = [];
            end
        end

        function post_job(self, projectId, job, worker)
            % Add a job to the api list, with a target worker

            payload = struct('name',job.name,'project',num2str(projectId),'worker',num2str(worker.id));
            if ~isempty(job.arguments)
                strArgs = job.arguments;
                for ii = 1:numel(job.arguments)
                    if isnumeric(job.arguments{ii})
                        strArgs{ii} = num2str(job.arguments{ii});
                    end
                end
                payload.args=strjoin(strArgs,',');
            end

            payloadJson = jsonencode(payload);
            payloadJson = strrep(payloadJson,'"','\"');
            % Construct curl command
            curlCommand = sprintf(['env -u LD_LIBRARY_PATH curl -k -sS -X POST %s ', ...
                '-H "Cookie: csrftoken=%s; sessionid=%s" ', ...
                '-H "X-CSRFToken: %s" ', ...
                '-H "Referer: %s" ', ...  % Add the Referer header
                '-H "Content-Type: application/json" ', ...
                '-d "%s"'], ... 
                [self.root_url 'jobs/'], self.csrfToken, self.sessionId, self.csrfToken, [self.root_url 'jobs/'], payloadJson);

            % disp(curlCommand)
            % Execute the command
            if self.isWindows;curlCommand=strrep(curlCommand,'env -u LD_LIBRARY_PATH ','');end
            [status, response] = system(curlCommand);
            % disp(response);
        end

        function self = post_assignment(self, job)
            % Construct curl command
            curlCommand = sprintf(['env -u LD_LIBRARY_PATH curl -k -sS -X POST %s ', ...
                '-H "Cookie: csrftoken=%s; sessionid=%s" ', ...
                '-H "X-CSRFToken: %s" ', ...
                '-H "Referer: %s" ', ...  % Add the Referer header
                '-H "Content-Type: application/json" ', ...
                '-d "{\\\"worker\\\":\\\"%i\\\", \\\"job\\\":\\\"%i\\\"', ...
                ', \\\"assigned\\\":\\\"1\\\"}"'], ...
                [self.root_url 'assignments/'], self.csrfToken, self.sessionId, self.csrfToken, [self.root_url 'assignments/'], self.worker_id, job.id);

            % disp(curlCommand)
            % Execute the command
            if self.isWindows;curlCommand=strrep(curlCommand,'env -u LD_LIBRARY_PATH ','');end
            [status, response] = system(curlCommand);

            % Display the response
            % disp(response);
            % check for 'must make a unique set' error
            if contains(response, 'must make a unique set')
                error('Assignment already exists');
            else
                disp(response)
                self.assignmentId = jsondecode(response).id;
            end
        end

        function self = job_started(self, job)
            assert(~isempty(self.assignmentId),"No assignment to start")

            % Patch the assignment entry to reflect that the job has started
            % Construct curl command
            curlCommand = sprintf(['env -u LD_LIBRARY_PATH curl -k -sS -X PATCH %s ', ...
                '-H "Cookie: csrftoken=%s; sessionid=%s" ', ...
                '-H "X-CSRFToken: %s" ', ...
                '-H "Referer: %s" ', ...  % Add the Referer header
                '-H "Content-Type: application/json" ', ...
                '-d {\\\"status\\\":\\\"started\\\"}'], ...
                [self.root_url 'assignments/' num2str(self.assignmentId) '/'], ...
                self.csrfToken, self.sessionId, self.csrfToken, self.root_url);

            % disp(curlCommand)
            % Execute the command
            if self.isWindows;curlCommand=strrep(curlCommand,'env -u LD_LIBRARY_PATH ','');end
            [status, response] = system(curlCommand);
        end

        function client = job_done(self, resultStr)
            assert(~isempty(self.assignmentId),"No assignment to finish")

            payload = struct('status','done','completed','1')
            if ~isempty(resultStr)
                payload.result = resultStr;
            end
            payload = jsonencode(payload);
            payload = strrep(payload, '"', '\"');

            % Patch the assignment entry to reflect that the job has finished
            % Construct curl command
            curlCommand = sprintf(['env -u LD_LIBRARY_PATH curl -k -sS -X PATCH %s ', ...
                '-H "Cookie: csrftoken=%s; sessionid=%s" ', ...
                '-H "X-CSRFToken: %s" ', ...
                '-H "Referer: %s" ', ...  % Add the Referer header
                '-H "Content-Type: application/json" ', ...
                '-d \"%s\"'], ...
                [self.root_url 'assignments/' num2str(self.assignmentId) '/'], ...
                self.csrfToken, self.sessionId, self.csrfToken, [self.root_url],payload);
            % disp(curlCommand)
            % Execute the command
            if self.isWindows;curlCommand=strrep(curlCommand,'env -u LD_LIBRARY_PATH ','');end
            [status, response] = system(curlCommand);
        end

        function job_failed(self, msg)
            % patch the result to reflect that the job has failed
            msg = OI.Compatibility.base64encode(msg);
            % Construct curl command
            curlCommand = sprintf(['env -u LD_LIBRARY_PATH curl -k -sS -X PATCH %s ', ...
                '-H "Cookie: csrftoken=%s; sessionid=%s" ', ...
                '-H "X-CSRFToken: %s" ', ...
                '-H "Referer: %s" ', ...  % Add the Referer header
                '-H "Content-Type: application/json" ', ...
                '-d "{\\\"status\\\":\\\"failed\\\",\\\"result\\\":\\\"%s\\\"}"'], ...
                [self.root_url 'assignments/' num2str(self.assignmentId) '/'], ...
                self.csrfToken, self.sessionId, self.csrfToken, [self.root_url 'assignments/' self.assignmentId], msg);
            % disp(curlCommand)
            % Execute the command
            if self.isWindows;curlCommand=strrep(curlCommand,'env -u LD_LIBRARY_PATH ','');end
            [status, response] = system(curlCommand);
        end


        function jsonJob = job2json(self, oiJob)
            if ~isa(oiJob, 'OI.Job')
                warning('Input should be an OI.Job object')
                return
            end
            jsonJob = struct('name', oiJob.name, 'arguments', {oiJob.arguments}, 'project', oiJob.project, 'target', '1');
        end

        function oiJob = json2job(self, json)
            if ~isstruct(json)
                warning('Input should be a struct')
                return
            end
            oiJob = OI.Job('name', json.name,'project',json.project);
            oiJob.target = '1';
            % oiJob.project = json.project;
            if isfield(json, 'args')
                oiJob.arguments = strsplit(json.args,',');
            end
        end

        function projObj = get_project_by_name(self, name)
            projects = self.list_projects();
            matchedProject = self.find_name_in_list(projects, name);
            projObj = self.parse_project(matchedProject);
        end

        function projObj = get_project_by_id(self,id)
            projects = self.list_projects();
            matchedProject = self.find_id_in_list(projects, id);
            if isempty(matchedProject)
                error('Project not found');
            end
            projObj = self.parse_project(matchedProject);
        end

        function projObj = parse_project(self, project)
            projObj = OI.Data.ProjectDefinition();
            projObj.PROJECT_NAME = project.name;
            projObj.START_DATE = OI.Data.Datetime(project.start_date,'yyyy-mm-dd');
            projObj.END_DATE = OI.Data.Datetime(project.end_date,'yyyy-mm-dd');
            
            projObj.AOI = self.parse_aoi(project.area_of_interest);
        end

        function aoiObj = parse_aoi(self, aoi)
            aoiList = self.list_aois();
            aoi = self.find_id_in_list(aoiList, aoi);
            aoiObj = OI.Data.AreaOfInterest(aoi.geometry);
        end

        function item = find_id_in_list(self, list, id)
            item = [];
            match = ...
                arrayfun(@(x) x.id == id, list);
            if any(match)
                match = find(match,1);
                item = list(match);
            end
        end

        function item = find_name_in_list(self, list, name)
            match = ...
                arrayfun(@(x) x.name == name, list);
            item = [];
            if any(match)
                match = find(match,1);
                item = list(match);
            end
        end

        function delete_worker(self,worker_id)
            % Construct curl command
            curlCommand = sprintf(['env -u LD_LIBRARY_PATH curl -k -sS -X DELETE %s ', ...
                '-H "Cookie: csrftoken=%s; sessionid=%s" ', ...
                '-H "X-CSRFToken: %s" ', ...
                '-H "Referer: %s" ', ...  % Add the Referer header
                ], ...
                [self.root_url 'workers/' num2str(worker_id) '/'], self.csrfToken, self.sessionId, self.csrfToken, [self.root_url 'workers/']);

            % Execute the command
            if self.isWindows;curlCommand=strrep(curlCommand,'env -u LD_LIBRARY_PATH ','');end
            [status, response] = system(curlCommand);

            % Display the response
            % disp(response);
        end

        function delete_assignment(self, assignment_id)
            % Construct curl command
            curlCommand = sprintf(['env -u LD_LIBRARY_PATH curl -k -sS -X DELETE %s ', ...
                '-H "Cookie: csrftoken=%s; sessionid=%s" ', ...
                '-H "X-CSRFToken: %s" ', ...
                '-H "Referer: %s" ', ...  % Add the Referer header
                ], ...
                [self.root_url 'assignments/' num2str(assignment_id) '/'], self.csrfToken, self.sessionId, self.csrfToken, [self.root_url 'assignments/']);

            % Execute the command
            if self.isWindows;curlCommand=strrep(curlCommand,'env -u LD_LIBRARY_PATH ','');end
            [status, response] = system(curlCommand);

            % Display the response
            % disp(response);
        end

        function delete_job(self, jobId) 
            % Construct curl command
            curlCommand = sprintf(['env -u LD_LIBRARY_PATH curl -k -sS -X DELETE %s ', ...
                '-H "Cookie: csrftoken=%s; sessionid=%s" ', ...
                '-H "X-CSRFToken: %s" ', ...
                '-H "Referer: %s" ', ...  % Add the Referer header
                ], ...
                [self.root_url 'jobs/' num2str(jobId) '/'], self.csrfToken, self.sessionId, self.csrfToken, [self.root_url 'jobs/']);

            % Execute the command
            if self.isWindows;curlCommand=strrep(curlCommand,'env -u LD_LIBRARY_PATH ','');end
            [status, response] = system(curlCommand);

            % Display the response
            % disp(response);
        end
    end

end

