classdef MessageBroker

properties
    % Define the event server properties
    serverPort = 3000; % Port number for server
    maxWorkers = 5; % Maximum number of workers
    workers = cell(maxWorkers, 1); % Cell array to store worker information
    availableWorkers = 1:maxWorkers; % Array to track available workers
end

methods
    function obj = MessageBroker()
    end

    function start(obj)
        % Create a TCP/IP server socket
        serverSocket = tcpip('0.0.0.0', serverPort, 'NetworkRole', 'server');
        set(serverSocket, 'InputBufferSize', 1024); % Set buffer size for incoming messages

        % Listen for connections
        disp('Event server is running...');
        fopen(serverSocket);
        disp('Waiting for connections...');

        while true
            % Accept incoming connection
            clientSocket = accept(serverSocket);
            disp('Client connected');
            
            % Read incoming message
            message = fread(clientSocket, clientSocket.BytesAvailable)';
            disp(['Received message: ' char(message)]);
            
            % Handle different message types
            switch char(message)
                case 'get_available_worker'
                    if isempty(availableWorkers)
                        response = 'No available workers';
                    else
                        % Get an available worker
                        workerID = availableWorkers(1);
                        availableWorkers = availableWorkers(2:end);
                        
                        % Simulate assigning a job to the worker
                        workers{workerID} = 'assigned';
                        response = ['Assigned worker: ' num2str(workerID)];
                    end
                    % Send response back to manager
                    fwrite(clientSocket, response);
                    
                % Add more cases for other message types
                
                otherwise
                    disp('Unknown message type');
                    % Send an error response back to manager
                    fwrite(clientSocket, 'Unknown message type');
            end
            
            % Close the client connection
            fclose(clientSocket);
            disp('Client disconnected');
        end

        % Clean up
        fclose(serverSocket);
        delete(serverSocket);

    end

end