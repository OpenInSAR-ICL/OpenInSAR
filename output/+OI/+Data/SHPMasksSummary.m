classdef SHPMasksSummary < OI.Data.DataObj
    properties
        generator = 'IdentifySHP'
        id = 'SHPMasksSummary'
    end % properties

    methods
        function this = SHPMasksSummary(varargin)
            this.hasFile = true;
            this.filepath = '$WORK$/SHPMasksSummary';
        end
    end % methods
end % classdef
