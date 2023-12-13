classdef PSI_Results_Summary < OI.Data.DataObj
    properties
        generator = 'PSI_Inversion'
        id = 'PSI_Results_Summary'
    end % properties

    methods
        function this = PSI_Results_Summary( varargin )
            this.hasFile = true;
            this.filepath = '$WORK$/PSI_Results_Summary';
        end
    end % methods
end % classdef