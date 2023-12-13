classdef GeoTiff < OI.Data.DataObj

properties
    % name = 'AsfQueryResults';
    id = '$TYPE$_stack_$STACK$_visit_$VISIT$_$DATE$';
    generator = 'GeoTiffs';
    STACK = '';
    VISIT = '';
    TYPE = '';
    DATE = '';
end%properties

methods
    function this = GeoTiff( ~ )
        this.hasFile = true;
        this.filepath = '$WORK$/geotiffs/$id$';
        this.fileextension = 'tif'; % TODO, get Tiff working!
        this.isUniqueName = true;
    end%ctor
end%methods

end%classdef