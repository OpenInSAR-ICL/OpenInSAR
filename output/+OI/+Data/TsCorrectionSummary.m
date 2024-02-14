classdef TsCorrectionSummary < OI.Data.DataObj
    properties
        generator = 'TsCorrection'
        id = 'TsCorrectionSummary'
    end % properties

    methods
        function this = TsCorrectionSummary( varargin )
            this.hasFile = true;
            this.filepath = '$WORK$/TsCorrectionSummary';
        end
    end % methods

    methods (Static = true)
       
    end % methods (Static = true)

end % classdef