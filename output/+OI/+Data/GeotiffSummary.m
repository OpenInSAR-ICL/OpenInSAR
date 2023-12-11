classdef GeotiffSummary < OI.Data.DataObj
    properties
        generator = 'GeoTiffs'
        id = 'GeotiffSummary'

    end % properties

    methods
        function this = GeotiffSummary( varargin )
            this.hasFile = true;
            this.filepath = '$WORK$/$id$';
        end
    end % methods

end % classdef