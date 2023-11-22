classdef FileSystemMessenger
    
    properties
        directory
    end % properties
    
    methods
        function this = FileSystemMessenger( workerInfo, endpoint )
            this.directory = endpoint;
            
        end
    end
    
end