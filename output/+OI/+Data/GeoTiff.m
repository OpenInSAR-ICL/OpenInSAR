classdef GeoTiff < OI.Data.DataObj

properties
    % name = 'AsfQueryResults';
    id = '$TYPE$_stack_$STACK$_burst_$SEGMENT$_visit_$VISIT$_$DATE$';
    generator = 'GeoTiffs';
    STACK = '';
    SEGMENT = '';
    VISIT = '';
    TYPE = '';
    DATE = '';
end%properties

methods
    function this = GeoTiff( ~ )
        this.hasFile = true;
        this.filepath = '$WORK$/geotiffs/$id$';
        this.fileextension = 'tiff'; % TODO, get Tiff working!
        this.isUniqueName = true;
    end%ctor
end%methods

end%classdef