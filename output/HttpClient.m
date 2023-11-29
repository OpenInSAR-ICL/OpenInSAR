% FILEPATH: /rds/user/saa116/home/OI_ICL_FORK/output/HttpClient.m
% HTTPCLIENT A simple HTTP client for Matlab. Finds a server based on info at '~/server_info.txt'.
% The server accepts POST requests at the root URL, which contain JSON
% data. The server responds with JSON data.
% The required JSON data is:
% 'sender_id': (string) The ID of the sender
% 'receiver_id': (string) The ID of the receiver
% 'data': (string) The data to be sent
% The response to a successful POST request is:
% {"message": "Message received"}
% 
% The server also accepts GET requests at the root URL. The response in 
% this case is all of the previously received messages in JSON format.
% E.g.:
% [{"sender_id": "sender1", "receiver_id": "receiver1", "message": "data1"}, {"sender_id": "sender2", "receiver_id": "receiver2", "message": "data2"}]
classdef HttpClient
    properties
        server_ip
        server_port
        server_url
        server_host
        my_hostname
        id
    end
    
    methods
        function obj = HttpClient()
            home_dir = getenv('HOME');
            
            % Check if HOME environment variable is set
            if isempty(home_dir)
                error('HOME environment variable is not set. Please set it to your home directory.');
            end
            
            server_info_file = fullfile(home_dir, 'server_info.txt');
            
            % Read server info from file
            try
                server_info = fileread(server_info_file);
            catch
                error('Could not read server info from file %s.', server_info_file);
            end
            
            % Split server info into IP and port
            fprintf(1,'Server info file: %s\n', server_info_file);
            fprintf(1,'Server info: %s\n', server_info);

            % split lines
            server_info = strsplit(server_info, '\n');
            % remove empty lines
            server_info = server_info(~cellfun(@isempty, server_info));
            % remove newlines
            server_info = cellfun(@(x) strrep(x, '\n', ''), server_info, 'UniformOutput', false);

            ip_line = server_info{1};
            port_line = server_info{2};
            % split IP line
            ip_line = strsplit(ip_line, ': ');
            obj.server_ip = ip_line{2};
            % split port line
            port_line = strsplit(port_line, ': ');
            obj.server_port = port_line{2};
            % split host line
            host_line = strsplit(server_info{3}, ': ');
            obj.server_host = host_line{2};
            obj.server_ip = obj.server_host;
            obj.my_hostname = getenv('HOSTNAME');
            
            % Create server URL
            obj.server_url = sprintf('http://%s:%s', obj.server_ip, obj.server_port);

            % Set the JSON headers
            web_options = weboptions('MediaType', 'application/json', 'ContentType', 'json');

            % Get the PBS array ID
            obj.id = getenv('PBS_ARRAY_INDEX');
            % If the PBS array ID is not set, use the hostname
            if isempty(obj.id)
                obj.id = getenv('HOSTNAME');
                % if its still empty use the username and a random number
                if isempty(obj.id)
                    obj.id = sprintf('%s_%d', getenv('USER'), randi(1000));
                end
            else
                % If the id isn't a string, convert it to one
                if ~ischar(obj.id)
                    obj.id = num2str(obj.id);
                end
            end

            % Set the json payload
            json_payload = struct('sender_id', obj.id, 'receiver_id', 'receiver1', 'message', 'data1');


            maxRetries = 10;
            originalTimeout = web_options.Timeout;
            for retries = 1:maxRetries
                % set timeout
                web_options.Timeout = 10;
                % Send a POST request along with the JSON payload
                try
                    response = webwrite(obj.server_url, json_payload, web_options);
                    break
                catch
                    error('Could not connect to server at %s. Please make sure the server is running.', obj.server_url);
                end
            end
            web_options.Timeout = originalTimeout;

            % Check if the response is correct
            if ~strcmp(response.message, 'Message received')
                error('Server did not respond correctly to POST request.');
            end

            % Now send a GET request to the server to ensure it has logged our POST request
            try
                response = webread(obj.server_url);
            catch
                error('Could not connect to server at %s. Please make sure the server is running.', obj.server_url);
            end
            disp(response)

            % The response might be:
            %  - empty
            %  - a struct array
            %  - a cell array

            % If the response is empty, there are no messages
            if numel(response) == 0 
                warning('no messages');
            elseif iscell(response)
                fprintf(1,'Msg is a cell array\n')
                % pass
            elseif isstruct(response) || (isarray(response) && isstruct(response(1)))
                % If the response is a struct array, convert it to a cell array
                fprintf(1,'Converting struct array to cell array\n')
                response_as_struct = response;
                response = cell(numel(response_as_struct), 1);
                for ii = 1:numel(response)
                    fprintf(1,'Converting struct %d to cell\n', ii)
                    response{ii} = response_as_struct(ii);
                end
            else
                warning('Unknown response type.');
                try
                    disp(response{1})
                catch
                    fprintf(1,'Msg is not cell form\n')
                    disp(response(1))
                end
                error('Unknown response type.');
            end

            % Print the messages
            for i = 1:numel(response)
                fprintf(1, 'Message %d:\n', i);
                assert(iscell(response)&&isstruct(response{i}));
                try
                    fprintf(1, 'Sender ID: %s\n', response{i}.sender_id);
                    fprintf(1, 'Receiver ID: %s\n', response{i}.receiver_id);
                    fprintf(1, 'message: %s\n', response{i}.message);
                catch

                end
            end

        end
    end
end
