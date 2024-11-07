classdef PSIUploadSummary < OI.Data.DataObj
    properties
        generator = 'PSIUploader'
        id = 'PSIUploadSummary'
    end % properties

    methods
        function this = PSIUploadSummary(varargin)
            this.hasFile = true;
            this.filepath = '$WORK$/PSIUploadSummary';
        end
    end % methods
end % classdef
