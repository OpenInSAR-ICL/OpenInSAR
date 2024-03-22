classdef ApsModelSummary < OI.Data.DataObj
    properties
        generator = 'ApsKriging2'
        id = 'ApsModelSummary'
    end % properties

    methods
        function this = BlockingSummary( varargin )
            this.hasFile = true;
            this.filepath = '$WORK$/ApsModelSummary';
        end
    end % methods

    methods (Static = true)
       
    end % methods (Static = true)

end % classdef