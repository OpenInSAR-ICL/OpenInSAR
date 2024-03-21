classdef PscSampleSummary < OI.Data.DataObj
    properties
        generator = 'PscSampling'
        id = 'PscSampleSummary'
    end % properties

    methods
        function this = PscSampleSummary( varargin )
            this.hasFile = true;
            this.filepath = '$WORK$/PscSampleSummary';
        end
    end % methods

    methods (Static = true)
       
    end % methods (Static = true)

end % classdef