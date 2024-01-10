classdef FileSystemMessenger < OI.MessengerBase
    
    properties
        directory
    end % properties
    
    methods
        function this = FileSystemMessenger( workerInfo, endpoint )
            this.directory = endpoint;
            
        end
        
        function this = connect( this, ~ )
            % do nothing
        end

        function this = send( this, ~ )
            % % write to file
            % fid = fopen( fullfile( this.directory, message.name ), 'w' );
            % fprintf( fid, '%s', message.data );
            % fclose( fid );
        end
    end
    
end