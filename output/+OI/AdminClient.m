classdef AdminClient
    properties
        base_client = [];
    end

    methods
        function self = AdminClient(host, username, password)
            if nargin == 3
                self.base_client = OI.BaseClient(host);
                self.base_client = self.base_client.login(username, password);
            else
                api_host = getenv('OI_API_HOST');
                username = getenv('OI_USERNAME');
                password = getenv('OI_PASSWORD');
                if isempty(api_host) || isempty(username) || isempty(password)
                    Aerror('AdminClient:AdminClient', ...
                        ['API host, username, password must be set', ...
                        ' by either arguments or environment variables']);
                end
                self.base_client = OI.BaseClient(api_host);
                self.base_client = self.base_client.login(username, password);
            end
        end
        function delete_all_workers(self)
            workers = self.base_client.list_workers();
            for worker = workers(:)'
                self.base_client.delete_worker(worker.id);
            end
        end
        function delete_all_assignments(self)
            assignments = self.base_client.list_assignments();
            for assignment = assignments(:)'
                self.base_client.delete_assignment(assignment.id);
            end
        end
        function delete_all_jobs(self)
            jobs = self.base_client.list_jobs();
            for job = jobs(:)'
                self.base_client.delete_job(job.id);
            end
        end
    end
end

