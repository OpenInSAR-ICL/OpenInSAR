classdef FieldSamplesSummary < OI.Data.DataObj
    properties
        generator = 'GetFieldSamples'
        id = 'FieldSamplesSummary'
    end % properties

    methods
        function this = FieldSamplesSummary( varargin )
            this.hasFile = true;
            this.filepath = '$WORK$/FieldSamplesSummary';
        end
    end % methods

    methods (Static = true)
       
    end % methods (Static = true)

end % classdef