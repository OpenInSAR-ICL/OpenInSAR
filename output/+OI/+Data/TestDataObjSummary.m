classdef TestDataObjSummary < OI.Data.DataObj
    properties
        generator = 'TestPlugin'
        id = 'TestDataObjSummary'
    end % properties

    methods
        function this = TestDataObjSummary( varargin )
            this.hasFile = true;
            this.filepath = '$WORK$/TestDataObjSummary';
        end
    end % methods

    methods (Static = true)
       
    end % methods (Static = true)

end % classdef